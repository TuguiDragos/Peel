import Foundation
internal import PeelPrivileged

/// The folders in a Caches folder that macOS keeps for its own services, which may be using them at any moment.
struct SystemCaches {
    /// The ones not named `com.apple.`, each with the part of the sealed system that carries its name.
    static let named: [String: String] = [
        "AMSDataMigratorTool": "/System/Library/PrivateFrameworks/AppleMediaServices.framework"
            + "/Versions/A/Resources/AMSDataMigratorTool",
        "assessmentagent": "/usr/libexec/assessmentagent",
        "AudioComponentRegistrar": "/System/Library/Frameworks/AudioToolbox.framework/AudioComponentRegistrar",
        "AudioConverterService": "/System/Library/Frameworks/AudioToolbox.framework/XPCServices/AudioConverterService.xpc",
        "betaenrollmentagent": "/usr/libexec/betaenrollmentagent",
        "CloudKit": "/System/Library/Frameworks/CloudKit.framework",
        "ColorSync": "/System/Library/ColorSync",
        "containermanagerd": "/usr/libexec/containermanagerd",
        "contentlinkingd": "/System/Library/PrivateFrameworks/Synapse.framework/Support/contentlinkingd",
        "CSExattrCryptoService": "/System/Library/PrivateFrameworks/CSExattrCrypto.framework/Versions/A/XPCServices"
            + "/CSExattrCryptoService.xpc",
        "Desktop Pictures": "/System/Library/Desktop Pictures",
        "diagnosticextensionsd": "/usr/libexec/diagnosticextensionsd",
        "duetexpertd": "/usr/libexec/duetexpertd",
        "FamilyCircle": "/System/Library/PrivateFrameworks/FamilyCircle.framework",
        "familycircled": "/System/Library/PrivateFrameworks/FamilyCircle.framework/Versions/A/Resources/familycircled",
        "gamed": "/usr/libexec/gamed",
        "GameKit": "/System/Library/Frameworks/GameKit.framework",
        "GameStoreKit": "/System/Library/PrivateFrameworks/GameStoreKit.framework",
        "GeoServices": "/System/Library/PrivateFrameworks/GeoServices.framework",
        "heard": "/System/Library/PrivateFrameworks/HearingCore.framework/heard",
        "homed": "/System/Library/PrivateFrameworks/HomeKitDaemon.framework/Support/homed",
        "HomeKit": "/System/Library/Frameworks/HomeKit.framework",
        "icdd": "/System/Library/Image Capture/Support/icdd",
        "itunescloudd": "/System/Library/PrivateFrameworks/iTunesCloud.framework/Support/itunescloudd",
        "mediaanalysisd-access": "/System/Library/PrivateFrameworks/MediaAnalysisAccess.framework/Versions/A/XPCServices"
            + "/mediaanalysisd-access.xpc",
        "metrickitd": "/usr/libexec/metrickitd",
        "mobiletimerd": "/System/Library/PrivateFrameworks/MobileTimer.framework/Executables/mobiletimerd",
        "PassKit": "/System/Library/Frameworks/PassKit.framework",
        "proactived": "/usr/libexec/proactived",
        "ptpcamerad": "/usr/libexec/ptpcamerad",
        "StatusKitAgent": "/System/Library/PrivateFrameworks/StatusKit.framework/StatusKitAgent",
        "studentd": "/usr/libexec/studentd",
        "talagent": "/System/Library/CoreServices/talagent",
        "watchlistd": "/System/Library/PrivateFrameworks/WatchListKit.framework/Support/watchlistd",
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
