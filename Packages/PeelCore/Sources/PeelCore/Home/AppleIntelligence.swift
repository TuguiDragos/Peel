import Foundation

/// What Apple says Apple Intelligence can keep on a Mac with macOS 27 (support.apple.com/121115): up to 14 GB on a Mac
/// with M3 or later and at least 12 GB of unified memory, up to 8 GB on any other Mac it names: M1 or later, and
/// MacBook Neo with A18 Pro.
public enum AppleIntelligence {
    public static let onThisMac = storage(
        chip: DeviceInfo.sysctl("machdep.cpu.brand_string") ?? "", memory: Int64(ProcessInfo.processInfo.physicalMemory)
    )

    static func storage(chip: String, memory: Int64) -> Int64? {
        if let generation = generation(of: chip, after: "Apple M"), generation >= 1 {
            return generation >= 3 && memory >= 12 * 1_073_741_824 ? 14_000_000_000 : 8_000_000_000
        }
        if let generation = generation(of: chip, after: "Apple A"), generation >= 18 {
            return 8_000_000_000
        }
        return nil
    }

    private static func generation(of chip: String, after name: String) -> Int? {
        guard chip.hasPrefix(name) else { return nil }
        return Int(chip.dropFirst(name.count).prefix { $0.isASCII && $0.isNumber })
    }
}
