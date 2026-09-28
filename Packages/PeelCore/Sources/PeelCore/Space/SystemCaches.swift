import Foundation
internal import PeelPrivileged

/// The folders in a Caches folder that macOS keeps for its own services, which may be using them at any moment.
struct SystemCaches {
    /// The ones not named `com.apple.`, each with the part of the sealed system that carries its name.
    static let named: [String: String] = [
        "AMSDataMigratorTool": "/System/Library/PrivateFrameworks/AppleMediaServices.framework"
            + "/Versions/A/Resources/AMSDataMigratorTool",
        "CloudKit": "/System/Library/Frameworks/CloudKit.framework",
        "ColorSync": "/System/Library/ColorSync",
        "containermanagerd": "/usr/libexec/containermanagerd",
        "Desktop Pictures": "/System/Library/Desktop Pictures",
        "FamilyCircle": "/System/Library/PrivateFrameworks/FamilyCircle.framework",
        "familycircled": "/System/Library/PrivateFrameworks/FamilyCircle.framework/Versions/A/Resources/familycircled",
        "GameKit": "/System/Library/Frameworks/GameKit.framework",
        "GeoServices": "/System/Library/PrivateFrameworks/GeoServices.framework",
        "homed": "/System/Library/PrivateFrameworks/HomeKitDaemon.framework/Support/homed",
        "HomeKit": "/System/Library/Frameworks/HomeKit.framework",
        "PassKit": "/System/Library/Frameworks/PassKit.framework",
    ]

    private static let lowercasedNames = Set(named.keys.map { $0.lowercased() })

    static func isMacOSs(_ name: String) -> Bool {
        ProtectedData.isApplesName(name) || lowercasedNames.contains(name.lowercased())
    }

    private let cachesFolders: Set<String>
    private let containerFolders: [[String]]

    init(environment: SearchEnvironment) {
        let locations = environment.locations
        cachesFolders = Set(locations.filter { $0.kind == .caches }.map { PathPattern.comparablePath(of: $0.url) })
        containerFolders = locations.filter { $0.kind == .containers || $0.kind == .groupContainers }
            .map { PathComponents.of(PathPattern.comparablePath(of: $0.url)) }
    }

    /// Whether macOS keeps `url` for itself: a folder in a Caches folder named for macOS, or anything in the container
    /// of one of Apple's own apps.
    func keeps(_ url: URL) -> Bool {
        if cachesFolders.contains(PathPattern.comparablePath(of: url.deletingLastPathComponent())) {
            return Self.isMacOSs(url.lastPathComponent)
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
