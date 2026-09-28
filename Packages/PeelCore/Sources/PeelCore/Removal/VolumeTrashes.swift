import Darwin
public import Foundation

/// The Trash an app thrown away from a disk other than the home's lands in: macOS keeps one for each account at the
/// top of each volume, `.Trashes/<uid>`, and makes it the first time something there goes to the Trash.
public enum VolumeTrashes {
    /// The Trash of each volume that holds one of `apps`, other than the home's, whose apps land in `~/.Trash`.
    public static func folders(forAppsAt apps: [URL], home: URL = .homeDirectory) -> [URL] {
        let homeVolume = volume(of: home)
        var folders: [URL] = []
        for app in apps {
            guard let volume = volume(of: app), volume != homeVolume else { continue }
            let trash = volume.appending(path: ".Trashes/\(getuid())", directoryHint: .isDirectory)
            if !folders.contains(trash) { folders.append(trash) }
        }
        return folders
    }

    private static func volume(of url: URL) -> URL? {
        (try? url.resourceValues(forKeys: [.volumeURLKey]))?.volume?.standardizedFileURL
    }
}
