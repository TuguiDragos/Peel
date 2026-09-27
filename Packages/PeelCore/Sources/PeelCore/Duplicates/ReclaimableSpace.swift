import Darwin
import Foundation

enum ReclaimableSpace {
    /// The bytes the file's blocks take on disk, which for a compressed or sparse file is less than its size.
    static func allocated(_ url: URL) -> Int64 {
        var info = stat()
        guard lstat(url.path(percentEncoded: false), &info) == 0 else { return 0 }
        return Int64(info.st_blocks) * 512
    }

    /// The bytes the file holds: its length less its holes, so a file made only of holes holds nothing. APFS
    /// keeps holes, while HFS+, FAT, and exFAT fill them in. A compressed file counts at its full length, since
    /// its few blocks (none when its bytes sit in an extended attribute) come from compression, not holes.
    static func held(_ info: stat) -> Int64 {
        info.st_flags & UInt32(UF_COMPRESSED) != 0 ? info.st_size : min(info.st_size, Int64(info.st_blocks) * 512)
    }

    /// The bytes removing the file would free: none while it has other hard links, and otherwise only the blocks
    /// it does not share with APFS clones or snapshots.
    static func of(_ url: URL) -> Int64 {
        let path = url.path(percentEncoded: false)
        var info = stat()
        guard lstat(path, &info) == 0, info.st_nlink <= 1 else { return 0 }
        // exFAT and FAT answer the private size with zero, though they share no block.
        guard canShareBlocks(path) else { return Int64(info.st_blocks) * 512 }
        let blocks = forkAttributes(of: path)
        // The private size counts only the data fork, while a compressed file keeps its bytes in its resource
        // fork or an extended attribute, which the private size leaves out. If the file was never cloned,
        // removing it frees every block; otherwise it counts as freeing nothing, since a clone may hold them all.
        if info.st_flags & UInt32(UF_COMPRESSED) != 0 {
            return blocks?.mayBeShared == false ? Int64(info.st_blocks) * 512 : 0
        }
        return blocks?.privateSize ?? Int64(info.st_blocks) * 512
    }

    /// Whether the disk `path` is on can clone a file or keep a snapshot, the only ways its files share blocks. True
    /// when the disk does not say.
    private static func canShareBlocks(_ path: String) -> Bool {
        var request = attrlist()
        request.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        request.volattr = attrgroup_t(ATTR_VOL_INFO) | attrgroup_t(ATTR_VOL_CAPABILITIES)
        // Layout: UInt32 length, then the capabilities, whose interfaces word holds cloning and snapshots.
        var buffer = [UInt8](repeating: 0, count: MemoryLayout<UInt32>.size + MemoryLayout<vol_capabilities_attr_t>.size)
        let status = buffer.withUnsafeMutableBytes { bytes in
            getattrlist(path, &request, bytes.baseAddress, bytes.count, 0)
        }
        guard status == 0 else { return true }
        let capabilities = buffer.withUnsafeBytes { bytes in
            bytes.loadUnaligned(fromByteOffset: MemoryLayout<UInt32>.size, as: vol_capabilities_attr_t.self)
        }
        let sharing = UInt32(VOL_CAP_INT_CLONE) | UInt32(VOL_CAP_INT_SNAPSHOT)
        let valid = capabilities.valid.1 & sharing
        return valid != sharing || capabilities.capabilities.1 & sharing != 0
    }

    private static func forkAttributes(of path: String) -> (privateSize: Int64?, mayBeShared: Bool?)? {
        var request = attrlist()
        request.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        request.commonattr = attrgroup_t(ATTR_CMN_RETURNED_ATTRS)
        request.forkattr = attrgroup_t(ATTR_CMNEXT_PRIVATESIZE | ATTR_CMNEXT_EXT_FLAGS)

        // Layout, with a place kept for each attribute asked for: UInt32 length, attribute_set_t of returned
        // attributes, then the private size and the extended flags.
        let returnedExtendedOffset = MemoryLayout<UInt32>.size * 5
        let sizeOffset = MemoryLayout<UInt32>.size * 6
        let flagsOffset = sizeOffset + MemoryLayout<Int64>.size
        var buffer = [UInt8](repeating: 0, count: 64)
        let status = buffer.withUnsafeMutableBytes { bytes in
            getattrlist(path, &request, bytes.baseAddress, bytes.count, UInt32(FSOPT_ATTR_CMN_EXTENDED | FSOPT_NOFOLLOW | FSOPT_PACK_INVAL_ATTRS))
        }
        guard status == 0 else { return nil }
        return buffer.withUnsafeBytes { bytes in
            let returned = bytes.loadUnaligned(fromByteOffset: returnedExtendedOffset, as: UInt32.self)
            return (
                returned & UInt32(ATTR_CMNEXT_PRIVATESIZE) != 0 ? bytes.loadUnaligned(fromByteOffset: sizeOffset, as: Int64.self) : nil,
                returned & UInt32(ATTR_CMNEXT_EXT_FLAGS) != 0
                    ? bytes.loadUnaligned(fromByteOffset: flagsOffset, as: UInt64.self) & UInt64(EF_MAY_SHARE_BLOCKS) != 0 : nil
            )
        }
    }
}
