public import Foundation
internal import PeelPrivileged

/// The folders the person chose for Peel to look for apps in, beside the Applications folders: another disk, or a
/// folder of tools. Every reading of the installed apps looks in them, in the app and in `peel` alike.
public struct AppFolders: Sendable {
    public enum Refusal: Sendable, Hashable {
        /// A whole disk, the home folder, a Library or its Application Support, or one of macOS's own folders, which
        /// would make every reading of the apps slow.
        case tooBroad
        /// An Applications folder, or a folder inside one that Peel already reads (`AppCatalog.depth`).
        case alreadyLookedIn
        /// The Trash, or a folder in it, which holds what is on its way out.
        case inATrash
        /// A folder iCloud or another cloud keeps, whose listing can download what it holds.
        case inTheCloud
    }

    /// A folder on the saved list Peel no longer reads, since a rule came after it was chosen.
    public struct LeftOut: Sendable, Hashable {
        public let folder: URL
        public let refusal: Refusal

        public init(folder: URL, refusal: Refusal) {
            self.folder = folder
            self.refusal = refusal
        }
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
        FileLock.whileReading(beside: url) { url.isMissing ? [] : read() }
    }

    /// Why the saved list can't be read, asked again once `load()` found it couldn't: nil when it can, or isn't there.
    public func whyUnreadable() -> FileProblem? {
        FileLock.whileReading(beside: url) { url.isMissing ? nil : readProblem() }
    }

    /// The folders the list holds that are no longer read, and why. One Peel reads anyway, as part of an Applications
    /// folder, loses nothing.
    public func leftOut() -> [LeftOut] {
        guard !url.isMissing else { return [] }
        return FileLock.whileReading(beside: url) {
            (saved() ?? []).compactMap { path in
                let folder = URL(filePath: path, directoryHint: .isDirectory)
                let refusal = Self.refusal(of: folder, home: home)
                return refusal.flatMap { $0 == .alreadyLookedIn ? nil : LeftOut(folder: folder, refusal: $0) }
            }
        }
    }

    @discardableResult
    public func add(_ folders: [URL]) -> ListChange {
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
            return .settingAside(url)
        }
    }

    @discardableResult
    public func remove(_ folders: [URL]) -> ListChange {
        let removed = Set(folders.map { PathPattern.comparablePath(of: $0) })
        return change { paths in
            paths.removeAll { removed.contains(PathPattern.comparablePath(of: URL(filePath: $0))) }
        }
    }

    /// Why `folder` is not taken, compared without case since the disk folds it.
    public static func refusal(of folder: URL, home: URL = .homeDirectory) -> Refusal? {
        refusal(of: folder, home: home) { $0.isInTheCloud }
    }

    static func refusal(of folder: URL, home: URL, isInTheCloud: (URL) -> Bool) -> Refusal? {
        // A link is read as where it leads, so that is what it is judged as too. `canonical` gives back a link it can't
        // follow, as to a disk that isn't connected, which is judged as itself.
        if folder.isSymbolicLink {
            let place = PathPattern.canonical(folder)
            if !place.isSymbolicLink, let refusal = refusal(of: place, home: home, isInTheCloud: isInTheCloud) {
                return refusal
            }
        }
        let path = folded(folder)
        let library = folded(home) + "/library"
        let broad = [
            "/", "/users", "/volumes", "/library", "/library/application support", folded(home), library,
            library + "/application support",
        ]
        if broad.contains(path) { return .tooBroad }
        // A whole disk other than the startup disk, and macOS's own folders, which hold no app of anyone else's.
        let names = PathComponents.of(path)
        if names.count == 2 && names[0] == "volumes" { return .tooBroad }
        // `/System/Volumes/Data` is every folder of the data volume again, under another name, so such a folder is
        // judged as what the kernel names it. What keeps that name is macOS's own.
        if names.first == "system" {
            let place = PathPattern.canonical(folder)
            guard PathComponents.of(folded(place)).first != "system" else { return .tooBroad }
            return refusal(of: place, home: home, isInTheCloud: isInTheCloud)
        }
        if TrashService.isAtOrInsideATrash(folder, home: home) { return .inATrash }
        // Listing a folder a cloud keeps can download what it holds.
        if isInTheCloud(folder) { return .inTheCloud }
        // A folder deeper than the reading of an Applications folder goes, or one it passes over, is taken.
        let lookedIn = AppCatalog.standardDirectories(home: home).contains { directory in
            let base = PathComponents.of(folded(directory))
            let levels = names.count - base.count
            guard levels >= 0, levels < AppCatalog.depth, names.starts(with: base) else { return false }
            return sequence(first: folder) { $0.deletingLastPathComponent() }.prefix(levels)
                .allSatisfy(AppCatalog.looksInside)
        }
        return lookedIn ? .alreadyLookedIn : nil
    }

    private static func folded(_ url: URL) -> String {
        PathPattern.comparablePath(of: url).lowercased()
    }

    private func change(_ edit: (inout [String]) -> Void) -> ListChange {
        FileLock.whileHeld(beside: url) {
            guard var paths = saved() ?? (url.isMissing ? [] : nil) else { return .notSaved(readProblem()) }
            edit(&paths)
            do {
                try PeelFolder.write(try JSONEncoder().encode(paths), to: url)
                return .saved
            } catch {
                return .notSaved(.failed(SystemError(error)))
            }
        }
    }

    /// Why the list there can't be read, or nil when it can, for a caller that holds the lock.
    private func readProblem() -> FileProblem? {
        guard let data = BoundedRead.data(at: url) else { return BoundedRead.whyUnreadable(url) }
        return (try? JSONDecoder().decode([String].self, from: data)) == nil ? .damaged : nil
    }

    /// The paths as saved, or nil when the file cannot be read.
    private func saved() -> [String]? {
        BoundedRead.data(at: url).flatMap { try? JSONDecoder().decode([String].self, from: $0) }
    }

    /// The folders saved, less any refused now, which a list saved before the folder was refused can hold.
    private func read() -> [URL]? {
        guard let paths = saved() else { return nil }
        return paths.map { URL(filePath: $0, directoryHint: .isDirectory) }
            .filter { Self.refusal(of: $0, home: home) == nil }
    }
}
