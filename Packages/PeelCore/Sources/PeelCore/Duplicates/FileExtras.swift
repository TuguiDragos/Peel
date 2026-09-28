import CryptoKit
import Darwin
import Foundation

/// What a copy carries besides its bytes, which moving it to the Trash takes away from where it was: its Finder tags
/// and its resource fork. Copies that differ in either are not duplicates.
enum FileExtras {
    /// The tags, in order, and a digest of the resource fork, as bytes to compare. Nil when the fork is there and
    /// cannot be read, since two copies are then not known to be alike.
    static func of(_ url: URL) -> [UInt8]? {
        var bytes: [UInt8] = []
        for tag in ((try? url.resourceValues(forKeys: [.tagNamesKey]).tagNames) ?? []).sorted() {
            bytes += Array(tag.utf8) + [0]
        }
        let path = url.path(percentEncoded: false)
        let size = getxattr(path, resourceFork, nil, 0, 0, XATTR_NOFOLLOW)
        guard size > 0 else { return bytes }
        var fork = [UInt8](repeating: 0, count: size)
        guard getxattr(path, resourceFork, &fork, size, 0, XATTR_NOFOLLOW) == size else { return nil }
        return bytes + [1] + Array(SHA256.hash(data: fork))
    }

    /// `XATTR_RESOURCEFORK_NAME` in `<sys/xattr.h>`.
    private static let resourceFork = "com.apple.ResourceFork"
}
