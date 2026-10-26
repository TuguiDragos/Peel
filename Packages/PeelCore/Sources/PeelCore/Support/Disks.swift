import DiskArbitration
import Foundation
internal import PeelPrivileged

/// What a mounted volume is, as DiskArbitration describes it.
enum Disks {
    /// Whether `url` is on a disk mounted under `/Volumes` that is not a disk image, which is mounted to install from
    /// and then thrown away.
    static func isOnAnotherDisk(_ url: URL) -> Bool {
        let names = PathComponents.of(url.path(percentEncoded: false))
        guard names.count > 2, names[0] == "Volumes", let volume = volume(mountedAt: "/Volumes/\(names[1])")
        else { return false }
        return !isADiskImage(volume)
    }

    /// DiskArbitration's description of the volume mounted at `path`, or nil when none is mounted exactly there.
    static func volume(mountedAt path: String) -> [String: Any]? {
        guard let session = DASessionCreate(kCFAllocatorDefault),
              let disk = DADiskCreateFromVolumePath(kCFAllocatorDefault, session, URL(filePath: path) as CFURL),
              let description = DADiskCopyDescription(disk) as? [String: Any],
              let mountPoint = description[kDADiskDescriptionVolumePathKey as String] as? URL,
              PathPattern.comparablePath(of: mountPoint) == PathPattern.comparablePath(of: URL(filePath: path))
        else { return nil }
        return description
    }

    static func isADiskImage(_ volume: [String: Any]) -> Bool {
        volume[kDADiskDescriptionDeviceModelKey as String] as? String == "Disk Image"
            || (volume[kDADiskDescriptionDevicePathKey as String] as? String)?.contains("/IOHDIXController/") == true
    }
}
