public import Foundation

/// Whether screenshots can be saved in a folder: `screencapture` saves nothing in one that isn't there or can't be
/// written to, and what it saves in the Trash goes when the Trash is emptied.
public enum ScreenshotFolder {
    public enum Problem: Sendable, Equatable {
        case notAFolder
        case inATrash
        case notWritable
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
