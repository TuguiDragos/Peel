public import Foundation
internal import PeelPrivileged

/// Saves an app's preference domains with `defaults export` before a reset clears them. History can put the
/// plists back only until the app writes new ones; a saved copy still works after that.
public enum PreferenceBackup {
    public static var defaultDirectory: URL {
        PeelFolder.url.appending(path: "Preference Backups", directoryHint: .isDirectory)
    }

    public enum Saved: Sendable, Equatable {
        /// None of the files being moved is a preference domain that exists.
        case nothingToSave
        case saved(URL)
        /// The copy could not be made, so the reset must not clear anything.
        case failed
    }

    /// What `defaults` answered: yes, no (it ran and said no, as for a domain that is not there), or nothing at
    /// all (it did not start, or ran out of time), which is never taken for a no.
    enum Answer: Sendable, Equatable {
        case yes
        case no
        case noAnswer
    }

    typealias Run = @Sendable ([String]) async -> Answer

    @concurrent
    public static func save(
        _ urls: [URL],
        for app: InstalledApp,
        in directory: URL = PreferenceBackup.defaultDirectory,
        exclusions: Exclusions = .none
    ) async -> Saved {
        await save(urls, for: app, in: directory, through: TrashService(exclusions: exclusions), run: run)
    }

    /// Exports every existing preference domain among `urls` into a new folder in `directory`. If any one
    /// cannot be copied, the result is `failed` and nothing may be cleared: the copy is what makes clearing safe.
    @concurrent
    static func save(_ urls: [URL], for app: InstalledApp, in directory: URL, through service: TrashService = TrashService(), run: Run) async -> Saved {
        var domains: [PreferenceCleanup.Domain] = []
        for domain in PreferenceCleanup.domains(for: urls, ownedBy: app.bundleIdentifier) {
            switch await run(domain.command("read")) {
            case .yes: domains.append(domain)
            case .no: continue
            case .noAnswer: return .failed
            }
        }
        guard !domains.isEmpty else { return .nothingToSave }

        // The bundle identifier comes from the app itself and becomes part of a folder name, so it must have the
        // reverse DNS shape `copies` reads back, which rules out a `/`. The folder must be new, or a second save
        // in the same second would write into the first one.
        guard Identifier.isReverseDNS(app.bundleIdentifier) else { return .failed }
        let folder = directory.appending(path: "\(app.bundleIdentifier) \(stamp())", directoryHint: .isDirectory)
        guard
            (try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)) != nil,
            (try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)) != nil
        else { return .failed }

        for domain in domains {
            let file = folder.appending(path: fileName(for: domain))
            guard await run(domain.command("export", file.path(percentEncoded: false))) == .yes, file.isThere else {
                // `rmdir` removes the folder only when it is empty. If copies were already written, the folder
                // goes to the Trash instead: nothing is deleted outright.
                if rmdir(folder.path(percentEncoded: false)) != 0 {
                    _ = await service.trash([folder])
                }
                return .failed
            }
        }
        return .saved(folder)
    }

    /// What putting a saved copy back came to.
    public struct Restored: Sendable, Equatable {
        /// Every domain in the copy went back.
        public let isComplete: Bool
        /// A domain was cleared and then did not go back, so the app starts that part from scratch.
        public let clearedSome: Bool
    }

    /// Puts the domains saved in `folder` back with `defaults import`. The app must not be running, or it
    /// overwrites them. `defaults import` merges rather than replaces, so each domain is deleted first.
    @concurrent
    public static func restore(from folder: URL) async -> Restored {
        await restore(from: folder, run: run)
    }

    static func restore(from folder: URL, run: Run) async -> Restored {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        let saved = files.filter { $0.pathExtension == "plist" }.compactMap { file in domain(from: file.lastPathComponent).map { ($0, file) } }
        guard !saved.isEmpty else { return Restored(isComplete: false, clearedSome: false) }
        var isComplete = true
        var clearedSome = false
        for (domain, file) in saved {
            // A copy that is not a readable property list would put nothing back once the delete had cleared the
            // settings in use, so it is refused before anything is cleared.
            guard isAPropertyList(file) else {
                isComplete = false
                continue
            }
            _ = await run(domain.command("delete"))
            if await run(domain.command("import", file.path(percentEncoded: false))) != .yes {
                isComplete = false
                clearedSome = true
            }
        }
        return Restored(isComplete: isComplete, clearedSome: clearedSome)
    }

    /// Whether `file` holds a property list whose top level is a dictionary, which is what `defaults import` reads.
    private static func isAPropertyList(_ file: URL) -> Bool {
        guard let data = BoundedRead.data(at: file, maximum: 64 * 1_024 * 1_024) else { return false }
        return (try? PropertyListSerialization.propertyList(from: data, format: nil)) is [String: Any]
    }

    /// One saved copy: whose settings, and when.
    public struct Copy: Sendable, Hashable, Identifiable {
        public let folder: URL
        public let bundleIdentifier: String
        public let date: Date

        public var id: URL { folder }
    }

    /// Lists the saved copies in `directory`, newest first. Only folders named the way `save` names them
    /// (bundle identifier, then time) count; anything else is ignored.
    public static func copies(in directory: URL = PreferenceBackup.defaultDirectory) -> [Copy] {
        let folders = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return folders.compactMap { folder -> Copy? in
            let name = folder.lastPathComponent
            guard folder.isRealFolder, name.count > stampLength + 1 else { return nil }
            let identifier = String(name.dropLast(stampLength + 1))
            guard Identifier.isReverseDNS(identifier), let date = try? stampStyle.parse(String(name.suffix(stampLength))) else { return nil }
            return Copy(folder: folder, bundleIdentifier: identifier, date: date)
        }
        .sorted { $0.date > $1.date }
    }

    static func fileName(for domain: PreferenceCleanup.Domain) -> String {
        domain.isByHost ? "\(domain.name).ByHost.plist" : "\(domain.name).plist"
    }

    static func domain(from fileName: String) -> PreferenceCleanup.Domain? {
        guard fileName.hasSuffix(".plist") else { return nil }
        var name = String(fileName.dropLast(".plist".count))
        let isByHost = name.hasSuffix(".ByHost")
        if isByHost {
            name = String(name.dropLast(".ByHost".count))
        }
        guard PreferenceCleanup.isUsableName(name) else { return nil }
        return PreferenceCleanup.Domain(name: name, isByHost: isByHost)
    }

    /// Formats a time as `2026-09-20 093000`, in local time, since people read the folder name in Finder.
    private static let stampStyle = Date.ISO8601FormatStyle(dateSeparator: .dash, dateTimeSeparator: .space, timeSeparator: .omitted, timeZone: .current)
        .year().month().day().time(includingFractionalSeconds: false)
    private static let stampLength = 17

    private static func stamp() -> String {
        Date.now.formatted(stampStyle)
    }

    /// Runs `defaults`: yes when it exits with status 0, no for any other status, and no answer when it did not
    /// run to its end. `save` checks that a domain exists with `read`, because `export` succeeds even for a domain
    /// that does not exist.
    private static func run(_ arguments: [String]) async -> Answer {
        guard case .success(let output) = await Subprocess.run("/usr/bin/defaults", arguments, timeout: 10) else {
            return .noAnswer
        }
        return output.status == 0 ? .yes : .no
    }
}
