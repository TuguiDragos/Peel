import Foundation

/// What macOS writes in the Logs folder at the top of the disk for its own services, each with the part of the
/// sealed system that names that path.
enum SystemLogs {
    static let named: [String: String] = [
        "CrashReporter": "/usr/libexec/DumpPanic",
        "hidfw-crashlogs": "/usr/libexec/sysdiagnosed",
        "LKDC-setup.log": "/usr/libexec/configureLocalKDC",
        "MCXTools.log": "/usr/libexec/mcxalr",
        "WindowServer": "/usr/libexec/sysdiagnosed",
        "Xsan": "/System/Library/Filesystems/acfs.fs/Contents/Resources/acfs.util",
    ]

    private static let lowercasedNames = Set(named.keys.map { $0.lowercased() })

    static func isMacOSs(_ name: String) -> Bool {
        lowercasedNames.contains(name.lowercased())
    }
}
