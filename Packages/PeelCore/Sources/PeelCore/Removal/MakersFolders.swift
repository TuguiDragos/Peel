import Darwin
import Foundation
internal import PeelPrivileged

/// The folders of the apps or their makers between a file an uninstall moved and its Library location, such as
/// `Application Support/MediaHuman`.
struct MakersFolders {
    /// Never the home folder's own top or `/Users/Shared`, which every account uses.
    static let kinds: Set<SearchLocation.Kind> = [.applicationSupport, .caches, .logs, .plugIns, .library]

    let environment: SearchEnvironment
    /// Lowercased, since disks ignore case by default.
    let names: Set<String>

    /// Each app's identifier and name, its maker's part of the identifier, and that part's last name. Never Apple's.
    static func names(of apps: [InstalledApp]) -> Set<String> {
        Set(apps.flatMap { app -> [String] in
            guard !ProtectedData.isApplesName(app.bundleIdentifier) else { return [] }
            let maker = Identifier.vendor(of: app.bundleIdentifier)
            return [app.bundleIdentifier, app.name, maker, maker?.split(separator: ".").last.map(String.init)]
                .compactMap { $0?.lowercased() }
        })
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
                  names.contains(folder.lastPathComponent.lowercased()) {
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
