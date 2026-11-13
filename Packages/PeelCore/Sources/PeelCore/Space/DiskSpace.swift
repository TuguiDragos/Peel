public import Foundation
internal import PeelPrivileged

/// A disk Space shows a band for, read on its own, as often as Home reads it, since a scan of the areas can be hours
/// old: the disk the home folder is on, and the startup disk too when the home is kept elsewhere.
public struct DiskSpace: Sendable, Hashable {
    public let storage: DeviceInfo.Storage
    /// Space macOS can reclaim by itself, mostly local snapshots and caches. Nil when the volume did not say.
    public let purgeable: Int64?
    /// The disk's name, as Finder shows it.
    public let name: String?
    /// The volume this disk's local snapshots are listed for: the startup disk's data, or the disk itself.
    public let snapshotVolume: String

    /// The disks Space shows for `home`, the startup disk first when the home folder is on another disk.
    @concurrent
    public static func readEach(home: URL = .homeDirectory) async -> [DiskSpace] {
        var disks: [DiskSpace] = []
        for place in places(home: home) {
            disks.append(await read(of: place))
        }
        return disks
    }

    static func snapshots(home: URL) async -> [DiskSnapshots] {
        var each: [DiskSnapshots] = []
        for place in places(home: home) {
            let volume = snapshotVolume(of: place)
            each.append(DiskSnapshots(volume: volume, snapshots: await LocalSnapshots.list(volume: volume)))
        }
        return each
    }

    /// A place on each disk Space shows: the home, after the startup disk when the home is kept elsewhere.
    private static func places(home: URL) -> [URL] {
        guard snapshotVolume(of: home) != LocalSnapshots.volume else { return [home] }
        return [URL(filePath: "/", directoryHint: .isDirectory), home]
    }

    @concurrent
    public static func read(of url: URL = .homeDirectory) async -> DiskSpace {
        DiskSpace(
            storage: DeviceInfo.storage(of: url), purgeable: purgeable(of: url),
            name: (try? url.resourceValues(forKeys: [.volumeLocalizedNameKey]))?.volumeLocalizedName,
            snapshotVolume: snapshotVolume(of: url)
        )
    }

    static func snapshotVolume(of url: URL) -> String {
        let path = url.path(percentEncoded: false)
        guard AccountTrash.areOnOneDisk(path, LocalSnapshots.volume) == false else { return LocalSnapshots.volume }
        return AccountTrash.top(ofTheDiskOf: path) ?? path
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
