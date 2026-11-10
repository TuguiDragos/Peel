import Darwin
public import Foundation

/// A folder opened only to be told of its changes, and the names it held then, read on a thread of their own within
/// `FileSize.budget`: a disk that sleeps, or a network volume that stopped answering, holds an `open` or a listing for
/// as long, and the main thread never waits for one.
public enum WatchedFolder {
    public enum Opening: Sendable {
        /// Its descriptor, opened with `O_EVTONLY`, which the caller closes, and the names in it then.
        case opened(descriptor: Int32, names: Set<String>)
        case missing
        /// macOS kept Peel from opening or listing it, and why, when that is known.
        case refused(FullDiskAccess.Refusal?)
        /// The disk didn't answer in time.
        case noAnswer
    }

    /// Opens `folder` and lists it with `listing`, which runs on the same thread.
    public static func open(
        _ folder: URL,
        listing: @escaping @Sendable (URL) -> Set<String>? = names(in:)
    ) async -> Opening {
        let path = folder.path(percentEncoded: false)
        let opening = await SlowRead.answer(within: FileSize.budget, discarding: close) { _ -> Opening in
            let descriptor = Darwin.open(path, O_EVTONLY)
            let failure = errno
            guard descriptor >= 0 else {
                return failure == ENOENT ? .missing : .refused(FullDiskAccess.Refusal(error: failure))
            }
            guard let names = listing(folder) else {
                Darwin.close(descriptor)
                return .refused(FullDiskAccess.whyUnlistable(folder))
            }
            return .opened(descriptor: descriptor, names: names)
        }
        return opening ?? .noAnswer
    }

    /// Opens `folder` alone, to be told when something appears in it, or nil when it can't be opened in time.
    public static func openToWait(in folder: URL) async -> Int32? {
        let path = folder.path(percentEncoded: false)
        let late: @Sendable (Int32?) -> Void = { descriptor in if let descriptor { Darwin.close(descriptor) } }
        let opened = await SlowRead.answer(within: FileSize.budget, discarding: late) { _ -> Int32? in
            let descriptor = Darwin.open(path, O_EVTONLY)
            return descriptor >= 0 ? descriptor : nil
        }
        return opened ?? nil
    }

    /// The names in `folder`, listed with `listing` within the budget, or nil when they can't be read in time.
    public static func list(
        _ folder: URL,
        listing: @escaping @Sendable (URL) -> Set<String>? = names(in:)
    ) async -> Set<String>? {
        await SlowRead.answer(within: FileSize.budget) { _ in listing(folder) } ?? nil
    }

    public static func names(in folder: URL) -> Set<String>? {
        (try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))).map(Set.init)
    }

    private static func close(_ opening: Opening) {
        if case .opened(let descriptor, _) = opening { Darwin.close(descriptor) }
    }
}
