public import Foundation

/// Whether screenshots can be saved in a folder: `screencapture` saves nothing in one that isn't there or can't be
/// written to, and what it saves in the Trash goes when the Trash is emptied.
public enum ScreenshotFolder {
    public enum Problem: Sendable, Equatable {
        case notAFolder
        case inATrash
        case notWritable
    }

    /// The path Peel writes for `folder`: one spelling, with no slash at the end, as a path written by hand.
    public static func setting(for folder: URL) -> String {
        PathPattern.comparablePath(of: folder)
    }

    /// Whether the folder a setting named before Peel changed it can no longer take screenshots. One on a disk that is
    /// not connected can't be told, and takes them again once the disk is back.
    static func cannotTakeScreenshots(_ path: String, home: URL = .homeDirectory) -> Bool {
        let folder = URL(filePath: path, directoryHint: .isDirectory)
        return !folder.isOnADiskNotConnected && problem(with: folder, home: home) != nil
    }

    /// `cannotTakeScreenshots`, off the caller's actor and within `budget`: a folder on a share that stopped answering
    /// can hold a read for as long as the network waits. Not knowing counts as a disk that is not connected.
    public static func hasGoneAway(_ path: String, home: URL = .homeDirectory) async -> Bool {
        await hasGoneAway(path, home: home, within: FileSize.budget) { cannotTakeScreenshots($0, home: $1) }
    }

    static func hasGoneAway(
        _ path: String, home: URL, within budget: TimeInterval, asking: @escaping @Sendable (String, URL) -> Bool
    ) async -> Bool {
        await SlowRead.answer(within: budget) { _ in asking(path, home) } ?? false
    }

    public static func takesScreenshots(
        _ folder: URL, home: URL = .homeDirectory, within budget: TimeInterval = FileSize.budget
    ) async -> Bool {
        await SlowRead.answer(within: budget) { _ in problem(with: folder, home: home) == nil } ?? false
    }

    public static func problem(with folder: URL, home: URL = .homeDirectory) -> Problem? {
        var isDirectory: ObjCBool = false
        let path = folder.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return .notAFolder
        }
        if TrashService.isAtOrInsideATrash(folder, home: home) { return .inATrash }
        return FileManager.default.isWritableFile(atPath: path) ? nil : .notWritable
    }
}
