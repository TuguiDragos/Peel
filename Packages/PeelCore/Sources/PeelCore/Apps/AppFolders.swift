public import Foundation
internal import PeelPrivileged

/// The folders the person chose for Peel to look for apps in, beside the Applications folders: another disk, or a
/// folder of tools. Every reading of the installed apps looks in them, in the app and in `peel` alike.
public struct AppFolders: Sendable {
    public enum Refusal: Sendable, Equatable {
        /// The disk, the home folder, or a folder of the system, which would make every reading of the apps slow.
        case tooBroad
        /// An Applications folder, or one inside it, which Peel already looks in.
        case alreadyLookedIn
        /// The Trash, or a folder in it, which holds what is on its way out.
        case inATrash
    }

    public let url: URL
    let home: URL

    public init(url: URL = AppFolders.defaultURL) {
        self.init(url: url, home: .homeDirectory)
    }

    init(url: URL, home: URL) {
        self.url = url
        self.home = home
    }

    public static var defaultURL: URL {
        url(inHome: .homeDirectory)
    }

    static func url(inHome home: URL) -> URL {
        PeelFolder.url(inHome: home).appending(path: "app-folders.json")
    }

    /// The folders chosen, or nil when the file is there and cannot be read: the apps in them are then not known.
    public func load() -> [URL]? {
        FileLock.whileHeld(beside: url) { url.isMissing ? [] : read() }
    }

    /// Adds `folders`. False when they could not be saved, or when the file is there and cannot be read, since
    /// writing over it would lose the folders it holds.
    @discardableResult
    public func add(_ folders: [URL]) -> Bool {
        change { paths in
            for path in folders.map({ PathPattern.comparablePath(of: $0) }) where !paths.contains(path) {
                paths.append(path)
            }
        }
    }

    /// Sets a list that cannot be read aside, under another name, so the folders can be chosen again.
    @discardableResult
    public func startOver() -> StartOver {
        FileLock.whileHeld(beside: url) {
            guard !url.isMissing, read() == nil else { return .notNeeded }
            return DamagedFile.setAside(url) == nil ? .couldNotSetAside : .started
        }
    }

    @discardableResult
    public func remove(_ folders: [URL]) -> Bool {
        let removed = Set(folders.map { PathPattern.comparablePath(of: $0) })
        return change { paths in
            paths.removeAll { removed.contains(PathPattern.comparablePath(of: URL(filePath: $0))) }
        }
    }

    /// Why `folder` is not taken, compared without case since the disk folds it.
    public static func refusal(of folder: URL, home: URL = .homeDirectory) -> Refusal? {
        let path = folded(folder)
        let broad = ["/", "/users", "/volumes", "/system", "/library", folded(home), folded(home) + "/library"]
        if broad.contains(path) { return .tooBroad }
        if TrashService.isAtOrInsideATrash(folder, home: home) { return .inATrash }
        let lookedIn = AppCatalog.standardDirectories(home: home).contains {
            PathComponents.isPath(path, atOrInside: folded($0))
        }
        return lookedIn ? .alreadyLookedIn : nil
    }

    private static func folded(_ url: URL) -> String {
        PathPattern.comparablePath(of: url).lowercased()
    }

    private func change(_ edit: (inout [String]) -> Void) -> Bool {
        FileLock.whileHeld(beside: url) {
            guard var paths = read().map({ $0.map { $0.path(percentEncoded: false) } }) ?? (url.isMissing ? [] : nil)
            else { return false }
            edit(&paths)
            guard let data = try? JSONEncoder().encode(paths) else { return false }
            let folder = url.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            return (try? data.write(to: url, options: .atomic)) != nil
        }
    }

    /// The folders saved, less any in a Trash, which a list saved before such a folder was refused can hold.
    private func read() -> [URL]? {
        guard let data = BoundedRead.data(at: url), let paths = try? JSONDecoder().decode([String].self, from: data)
        else { return nil }
        return paths.map { URL(filePath: $0, directoryHint: .isDirectory) }
            .filter { !TrashService.isAtOrInsideATrash($0, home: home) }
    }
}
