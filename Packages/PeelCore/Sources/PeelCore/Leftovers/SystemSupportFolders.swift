import Foundation

/// What macOS keeps in an Application Support folder for its own services, each name with the part of the sealed
/// system that carries it, as `SystemCaches` does for caches.
enum SystemSupportFolders {
    static let named: [String: String] = [
        "ApplePushService": "/System/Library/PrivateFrameworks/ApplePushService.framework",
    ]

    private static let lowercasedNames = Set(named.keys.map { $0.lowercased() })

    static func isMacOSs(_ name: String) -> Bool {
        lowercasedNames.contains(name.lowercased())
    }
}
