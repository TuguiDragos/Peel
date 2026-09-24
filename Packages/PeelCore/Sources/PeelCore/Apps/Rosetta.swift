import Darwin
import Foundation

/// The processor of the Mac that Peel runs on. macOS 26 still installs on Intel Macs, where Intel software runs
/// natively and Rosetta does not exist, so nothing there needs translating.
public enum HostArchitecture {
    public static var isAppleSilicon: Bool {
        integer("hw.optional.arm64") == 1
    }

    static func integer(_ name: String) -> Int? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return Int(value)
    }
}

/// Tells whether Rosetta is installed, which an Apple silicon Mac needs to run Intel software.
///
/// Upgrading to macOS 27 does not restore Rosetta, so a Mac that ran Intel apps before the upgrade may not run
/// them after it. An Intel app there does not run at all, so it must not be described as running through Rosetta.
public enum Rosetta {
    static let paths = [
        "/Library/Apple/usr/share/rosetta/rosetta",
        "/Library/Apple/usr/libexec/oah/libRosettaRuntime",
    ]

    public static var isInstalled: Bool {
        installed(among: paths)
    }

    static func installed(among paths: [String]) -> Bool {
        paths.contains { FileManager.default.fileExists(atPath: $0) }
    }
}
