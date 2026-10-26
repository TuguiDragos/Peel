public import Foundation

/// The disk the home folder is on, as Space's band shows it: read on its own, as often as Home reads it, since a scan
/// of the areas can be hours old.
public struct DiskSpace: Sendable, Hashable {
    public let storage: DeviceInfo.Storage
    /// Space macOS can reclaim by itself, mostly local snapshots and caches. Nil when the volume did not say.
    public let purgeable: Int64?

    @concurrent
    public static func read(of home: URL = .homeDirectory) async -> DiskSpace {
        DiskSpace(storage: DeviceInfo.storage(of: home), purgeable: purgeable(of: home))
    }

    static func purgeable(of url: URL) -> Int64? {
        let values = try? url.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey,
        ])
        guard let important = values?.volumeAvailableCapacityForImportantUsage,
              let free = values?.volumeAvailableCapacity else { return nil }
        return max(0, important - Int64(free))
    }
}
