import Foundation
internal import PeelPrivileged

/// What macOS keeps for its own services in a Caches or a Logs folder, which those services may be using at any moment.
struct MacOSsOwnItems {
    private let folders: [String: SearchLocation.Kind]
    private let containerFolders: [[String]]

    init(environment: SearchEnvironment) {
        let locations = environment.locations
        folders = Dictionary(
            locations.filter { $0.kind == .caches || $0.kind == .logs }
                .map { (PathPattern.comparablePath(of: $0.url), $0.kind) },
            uniquingKeysWith: { first, _ in first }
        )
        containerFolders = locations.filter { $0.kind == .containers || $0.kind == .groupContainers }
            .map { PathComponents.of(PathPattern.comparablePath(of: $0.url)) }
    }

    /// Whether macOS keeps `url` for itself: an item in a Caches or a Logs folder named as macOS names its own there,
    /// or anything in the container of one of Apple's own apps.
    func contains(_ url: URL) -> Bool {
        if let kind = folders[PathPattern.comparablePath(of: url.deletingLastPathComponent())] {
            let name = url.lastPathComponent
            return ProtectedData.isApplesName(name) || SystemFolders.keeps(name, in: kind)
        }
        return container(holding: url).map(ProtectedData.isApplesName) ?? false
    }

    /// The identifier of the app container or the group container `url` is in: the name of that container's folder.
    func container(holding url: URL) -> String? {
        let names = PathComponents.of(PathPattern.comparablePath(of: url))
        guard let folder = containerFolders.first(where: { names.count > $0.count && names.starts(with: $0) }) else {
            return nil
        }
        return names[folder.count]
    }
}
