import Darwin
public import Foundation

/// The file of one of this account's launch agents, opened to be edited. Saving moves the file as it is to the Trash,
/// where History can put it back, writes the person's text in its place as typed, and loads the job again when
/// launchd had it.
public struct LaunchAgentFile: Sendable {
    /// Why the file can't be opened, or an edit can't be saved.
    public enum Problem: Error, Sendable, Hashable {
        /// Not one of the agents `BackgroundItem.canBeEdited` allows.
        case cannotBeEdited
        /// A link, a folder, or nothing at all where the file was.
        case notAPlainFile
        case notYours
        case tooLarge
        case unreadable
        /// The file changed since it was opened.
        case changed
        case notAPropertyList(line: Int?)
        case notADictionary
        /// The label is gone or another, while it names the job launchd has.
        case labelChanged
        /// Neither `Program` nor `ProgramArguments`, one of which `launchd.plist(5)` requires.
        case noProgram
        case programIsNotText
        case argumentsAreNotText
        /// The file as it is couldn't move to the Trash.
        case notMoved(TrashFailure.Reason)
        case notWritten(SystemError)
        /// The new file was made, but not all of it was written.
        case incomplete(SystemError)
    }

    /// Why launchd doesn't run the job from the new file yet, though it had the job before the edit.
    public enum Reload: Sendable, Hashable {
        /// launchd didn't stop the job, so it runs as before until the person logs out.
        case notStopped(BackgroundItemActions.Failure)
        case notStarted(BackgroundItemActions.Failure)
    }

    public enum Outcome: Sendable {
        /// The new file is in place, and `moved` holds the old one, now in the Trash.
        case saved(moved: TrashResult, reload: Reload?)
        /// Nothing changed. `moved` holds the refusal of the move, if it was refused.
        case unchanged(Problem, moved: TrashResult)
        /// The old file is in the Trash, and the new one isn't whole in its place.
        case oldFileInTheTrash(Problem, moved: TrashResult)

        /// What moved to the Trash and what was refused, to be written down like any other removal.
        public var moved: TrashResult {
            switch self {
            case .saved(let moved, _), .unchanged(_, let moved), .oldFileInTheTrash(_, let moved): moved
            }
        }
    }

    enum Written: Sendable, Equatable {
        case written
        case notMade(SystemError)
        case incomplete(SystemError)
    }

    /// 1 MB, far more than a job's file holds.
    static let maximumBytes = 1_024 * 1_024

    public let url: URL
    public let label: String
    /// The file as XML: as written, or converted from the binary form.
    public let text: String
    let opened: FileIdentity
    let mode: mode_t

    @concurrent
    public static func open(_ item: BackgroundItem) async -> Result<LaunchAgentFile, Problem> {
        await open(item, owner: getuid())
    }

    @concurrent
    static func open(_ item: BackgroundItem, owner: uid_t) async -> Result<LaunchAgentFile, Problem> {
        guard item.canBeEdited, let url = item.plistURL else { return .failure(.cannotBeEdited) }
        var info = stat()
        guard lstat(url.path(percentEncoded: false), &info) == 0, info.st_mode & S_IFMT == S_IFREG else {
            return .failure(.notAPlainFile)
        }
        guard info.st_uid == owner else { return .failure(.notYours) }
        guard info.st_size <= maximumBytes else { return .failure(.tooLarge) }
        guard let (data, identity) = BoundedRead.contents(at: url, maximum: maximumBytes),
              identity.holdsTheSameContents(as: FileIdentity(info))
        else { return .failure(.unreadable) }
        var format = PropertyListSerialization.PropertyListFormat.xml
        guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: &format),
              (plist as? [String: Any])?["Label"] as? String == item.label
        else { return .failure(.changed) }
        let text: String
        if format == .xml, let written = String(data: data, encoding: .utf8) {
            text = written
        } else if let xml = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) {
            text = String(decoding: xml, as: UTF8.self)
        } else {
            return .failure(.unreadable)
        }
        return .success(
            LaunchAgentFile(url: url, label: item.label, text: text, opened: identity, mode: info.st_mode & 0o7777)
        )
    }

    /// What keeps `text` from being saved, or nil: launchd needs a dictionary naming the same job and what it runs.
    public func problem(in text: String) -> Problem? {
        let plist: Any
        do {
            plist = try PropertyListSerialization.propertyList(from: Data(text.utf8), options: [], format: nil)
        } catch {
            return .notAPropertyList(line: Self.line(of: error))
        }
        guard let job = plist as? [String: Any] else { return .notADictionary }
        guard job["Label"] as? String == label else { return .labelChanged }
        let program = job["Program"]
        let arguments = job["ProgramArguments"]
        guard program != nil || arguments != nil else { return .noProgram }
        if program != nil, (program as? String ?? "").isEmpty { return .programIsNotText }
        if let arguments {
            guard let list = arguments as? [Any], !list.isEmpty, list.allSatisfy({ $0 is String }) else {
                return .argumentsAreNotText
            }
        }
        return nil
    }

    /// The line Foundation names when it can't read a property list, as in "Close tag on line 5".
    private static func line(of error: any Error) -> Int? {
        let account = (error as NSError).userInfo[NSDebugDescriptionErrorKey] as? String ?? ""
        return account.firstMatch(of: /line (\d+)/).flatMap { Int($0.output.1) }
    }

    @concurrent
    public func save(_ text: String, for item: BackgroundItem, exclusions: Exclusions) async -> Outcome {
        let trash = TrashService(exclusions: exclusions)
        return await save(
            text, for: item, trash: trash,
            stop: { item in
                do throws(BackgroundItemActions.Failure) {
                    try await BackgroundItemActions.stop(item)
                    return nil
                } catch {
                    return error
                }
            },
            start: { item throws(BackgroundItemActions.Failure) in try await BackgroundItemActions.start(item) },
            putBack: { await trash.restore([$0]).failures.first ?? nil }
        )
    }

    /// Checks `text` and the file first, so a refused edit moves nothing. The move is the one Move to Trash makes, and
    /// the new file goes only where nothing is: should it not be made, the old one goes back.
    func save(
        _ text: String,
        for item: BackgroundItem,
        trash: TrashService,
        stop: (BackgroundItem) async -> BackgroundItemActions.Failure?,
        start: (BackgroundItem) async throws(BackgroundItemActions.Failure) -> Void,
        putBack: (TrashedItem) async -> RestoreFailure?,
        makeFile: (URL, Data, mode_t) -> Written = LaunchAgentFile.makeFile(at:holding:mode:)
    ) async -> Outcome {
        if let problem = problem(in: text) { return .unchanged(problem, moved: TrashResult()) }
        guard FileIdentity.of(url)?.holdsTheSameContents(as: opened) == true else {
            return .unchanged(.changed, moved: TrashResult())
        }
        let moved: BackgroundItemActions.Moved
        do {
            moved = try await BackgroundItemActions.moveToTrash(item, isHelperEnabled: false, trash: trash, stop: stop)
        } catch {
            return .unchanged(.cannotBeEdited, moved: TrashResult())
        }
        guard let old = moved.result.trashed.first else {
            let problem = moved.result.failures.first.map { Problem.notMoved($0.reason) } ?? .changed
            return .unchanged(problem, moved: moved.result)
        }
        var result = moved.result
        switch makeFile(url, Data(text.utf8), mode) {
        case .written:
            result.trashed[0].replacedBy = TrashedItem.Identity(ofItemAt: url)
        case .notMade(let error):
            guard await putBack(old) != nil else { return .unchanged(.notWritten(error), moved: TrashResult()) }
            return .oldFileInTheTrash(.notWritten(error), moved: moved.result)
        case .incomplete(let error):
            return .oldFileInTheTrash(.incomplete(error), moved: moved.result)
        }
        guard item.state != .notLoaded, item.state != .unknown else { return .saved(moved: result, reload: nil) }
        if let stillRunning = moved.stillRunning {
            return .saved(moved: result, reload: .notStopped(stillRunning))
        }
        var stopped = item
        stopped.state = .notLoaded
        do throws(BackgroundItemActions.Failure) {
            try await start(stopped)
            return .saved(moved: result, reload: nil)
        } catch {
            return .saved(moved: result, reload: .notStarted(error))
        }
    }

    /// Makes the file at `url` holding `data`, never over anything already there and never through a link, then gives
    /// it `mode`, which the mask of new files can't cut once the file exists.
    static func makeFile(at url: URL, holding data: Data, mode: mode_t) -> Written {
        let flags = O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC
        let descriptor = Darwin.open(url.path(percentEncoded: false), flags, 0o600)
        guard descriptor >= 0 else { return .notMade(.posix(errno)) }
        defer { close(descriptor) }
        let failure: Int32? = data.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return nil }
            var written = 0
            while written < bytes.count {
                let count = Darwin.write(descriptor, base + written, bytes.count - written)
                if count > 0 {
                    written += count
                } else if count < 0, errno == EINTR {
                    continue
                } else {
                    return count < 0 ? errno : EIO
                }
            }
            return nil
        }
        if let failure { return .incomplete(.posix(failure)) }
        // Should this fail, the file stays readable by its owner alone, which launchd loads all the same.
        _ = fchmod(descriptor, mode)
        return fsync(descriptor) == 0 ? .written : .incomplete(.posix(errno))
    }
}

private extension SystemError {
    static func posix(_ code: Int32) -> SystemError {
        SystemError(domain: NSPOSIXErrorDomain, code: Int(code))
    }
}
