import Foundation
internal import PeelPrivileged

/// The folders in a Caches folder that macOS keeps for its own services, which may be using them at any moment.
enum SystemCaches {
    /// The ones not named `com.apple.`, each with the part of the sealed system that carries its name.
    static let named: [String: String] = [
        "AMSDataMigratorTool": "/System/Library/PrivateFrameworks/AppleMediaServices.framework"
            + "/Versions/A/Resources/AMSDataMigratorTool",
        "CloudKit": "/System/Library/Frameworks/CloudKit.framework",
        "containermanagerd": "/usr/libexec/containermanagerd",
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
}
