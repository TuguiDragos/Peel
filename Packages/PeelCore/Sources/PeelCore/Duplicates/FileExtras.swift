import CryptoKit
import Darwin
import Foundation

/// What a copy carries besides its bytes, which moving it to the Trash takes away from where it was: its Finder tags,
/// its resource fork, and its Finder comment. Copies that differ in any of them are not duplicates.
enum FileExtras {
    /// The tags, in order, and a digest of the resource fork and of the comment, as bytes to compare. Nil when one
    /// of those is there and cannot be read, since two copies are then not known to be alike.
    static func of(_ url: URL) -> [UInt8]? {
        var bytes: [UInt8] = []
        for tag in ((try? url.resourceValues(forKeys: [.tagNamesKey]).tagNames) ?? []).sorted() {
            bytes += Array(tag.utf8) + [0]
        }
        let path = url.path(percentEncoded: false)
        for (mark, name) in [(UInt8(1), resourceFork), (UInt8(2), finderComment)] {
            let size = getxattr(path, name, nil, 0, 0, XATTR_NOFOLLOW)
            guard size > 0 else { continue }
            var value = [UInt8](repeating: 0, count: size)
            guard getxattr(path, name, &value, size, 0, XATTR_NOFOLLOW) == size else { return nil }
            bytes += [mark] + Array(SHA256.hash(data: value))
        }
        return bytes
    }

    /// `XATTR_RESOURCEFORK_NAME` in `<sys/xattr.h>`.
    private static let resourceFork = "com.apple.ResourceFork"
    /// Where the Finder keeps a file's comment, which Spotlight reads as `kMDItemFinderComment`.
    private static let finderComment = "com.apple.metadata:kMDItemFinderComment"
}
