import Foundation

/// How many entries a folder holds, asked of its file system rather than read.
public enum FolderEntries {
    /// The most entries Peel reads of a folder to make sure nothing it protects is inside.
    public static let lookLimit = 100_000

    /// The number of entries in the folder at `path`, without reading them, when its file system keeps it.
    public static func count(at path: String) -> Int? {
        var request = attrlist()
        request.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        request.commonattr = attrgroup_t(ATTR_CMN_RETURNED_ATTRS)
        request.dirattr = attrgroup_t(ATTR_DIR_ENTRYCOUNT)
        // UInt32 length, the attribute_set_t of what was returned (its third word the folder's), then the count.
        var buffer = [UInt8](repeating: 0, count: 64)
        let status = buffer.withUnsafeMutableBytes { bytes in
            getattrlist(path, &request, bytes.baseAddress, bytes.count, UInt32(FSOPT_PACK_INVAL_ATTRS))
        }
        guard status == 0 else { return nil }
        return buffer.withUnsafeBytes { bytes in
            let returned = bytes.loadUnaligned(fromByteOffset: MemoryLayout<UInt32>.size * 3, as: UInt32.self)
            guard returned & UInt32(ATTR_DIR_ENTRYCOUNT) != 0 else { return nil }
            return Int(bytes.loadUnaligned(fromByteOffset: MemoryLayout<UInt32>.size * 6, as: UInt32.self))
        }
    }

    /// Whether `path` holds more than `limit` entries, counted as Foundation lists them where no number is kept.
    static func holdMore(than limit: Int, at path: String) -> Bool {
        if let count = count(at: path) { return count > limit }
        let folder = URL(filePath: path, directoryHint: .isDirectory).resolvingSymlinksInPath()
        guard let entries = FileManager.default.enumerator(
            at: folder, includingPropertiesForKeys: [], options: [.skipsSubdirectoryDescendants]
        ) else { return false }
        var count = 0
        while entries.nextObject() != nil {
            count += 1
            if count > limit { return true }
        }
        return false
    }
}
