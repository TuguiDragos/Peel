import Darwin
public import Foundation
internal import PeelPrivileged

/// The Trash an app thrown away from a disk other than the home's lands in: macOS keeps one for each account at the
/// top of each volume, `.Trashes/<uid>`, and makes it the first time something there goes to the Trash.
public enum VolumeTrashes {
    /// The Trash of each volume that holds one of `apps`, other than the home's, whose apps land in `~/.Trash`.
    public static func folders(forAppsAt apps: [URL], home: URL = .homeDirectory) -> [URL] {
        let homeTrash = homeTrash(of: home)
        var folders: [URL] = []
        for folder in apps.map({ trash(forItemAt: $0, home: home) }) where folder != homeTrash {
            if !folders.contains(folder) { folders.append(folder) }
        }
        return folders
    }

    /// The Trash an item at `url` lands in: `home`'s for one on the home's disk, else the one at the top of its own
    /// (`AccountTrash`), which for the startup disk is at the top of its data, not at `/`.
    static func trash(forItemAt url: URL, home: URL = .homeDirectory) -> URL {
        let folder = url.deletingLastPathComponent().path(percentEncoded: false)
        guard let top = AccountTrash.top(ofTheDiskOf: folder) else { return homeTrash(of: home) }
        let trash = AccountTrash.folder(for: getuid(), home: home.path(percentEncoded: false), onTheDiskAt: top)
        return URL(filePath: trash, directoryHint: .isDirectory)
    }

    private static func homeTrash(of home: URL) -> URL {
        home.appending(path: ".Trash", directoryHint: .isDirectory)
    }
}
