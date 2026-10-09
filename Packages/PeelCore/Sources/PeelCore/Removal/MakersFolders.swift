import Darwin
import Foundation
internal import PeelPrivileged

/// The folders of the apps or their makers between a file an uninstall moved and its Library location, such as
/// `Application Support/MediaHuman`.
struct MakersFolders {
    /// Never the home folder's own top or `/Users/Shared`, which every account uses.
    static let kinds: Set<SearchLocation.Kind> = [.applicationSupport, .caches, .logs, .plugIns, .library]

    let environment: SearchEnvironment
    /// As `Naming.folderName` writes them, so case and punctuation never tell two names apart.
    let names: Set<String>

    /// The folder names of each app and its maker (`InstalledApp.ownFolderNames`). Never Apple's.
    static func names(of apps: [InstalledApp]) -> Set<String> {
        Set(apps.filter { !ProtectedData.isApplesName($0.bundleIdentifier) }.flatMap(\.ownFolderNames))
    }

    /// Deepest first. A folder with another name stops the walk, since it may be any app's.
    func above(_ moved: [URL]) -> [URL] {
        let locations = environment.locations
        let ends = Set(locations.map { PathPattern.comparablePath(of: $0.url) })
        let places = locations.filter { Self.kinds.contains($0.kind) }.map { PathPattern.comparablePath(of: $0.url) }
        var folders: [String: URL] = [:]
        for url in moved {
            var folder = url.deletingLastPathComponent()
            var path = PathPattern.comparablePath(of: folder)
            while !ends.contains(path), places.contains(where: { PathComponents.isPath(path, inside: $0) }),
                  names.contains(Naming.folderName(folder.lastPathComponent)) {
                folders[path] = folder
                folder = folder.deletingLastPathComponent()
                path = PathPattern.comparablePath(of: folder)
            }
        }
        return folders.sorted { PathComponents.of($0.key).count > PathComponents.of($1.key).count }.map(\.value)
    }

    /// Read without the trailing slash, which would follow a link.
    static func isEmpty(_ folder: URL) -> Bool {
        let path = PathPattern.comparablePath(of: folder)
        var info = stat()
        guard lstat(path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR else { return false }
        return (try? FileManager.default.contentsOfDirectory(atPath: path))?.isEmpty == true
    }
}
