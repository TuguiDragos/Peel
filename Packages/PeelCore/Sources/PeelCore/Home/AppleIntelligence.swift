import Foundation

/// What Apple says Apple Intelligence can keep on a Mac with macOS 27 (support.apple.com/121115): up to 14 GB on a Mac
/// with M3 or later and at least 12 GB of unified memory, up to 8 GB on any other Mac with M1 or later.
public enum AppleIntelligence {
    public static let onThisMac = storage(
        chip: DeviceInfo.sysctl("machdep.cpu.brand_string") ?? "", memory: Int64(ProcessInfo.processInfo.physicalMemory)
    )

    static func storage(chip: String, memory: Int64) -> Int64? {
        let name = "Apple M"
        guard chip.hasPrefix(name),
              let generation = Int(chip.dropFirst(name.count).prefix { $0.isASCII && $0.isNumber }), generation >= 1
        else { return nil }
        return generation >= 3 && memory >= 12 * 1_073_741_824 ? 14_000_000_000 : 8_000_000_000
    }
}
