import Foundation

/// The images of this Mac's dyld shared cache, read from the cache's own headers (`dyld_cache_format.h`): the main
/// file's table of image text says where each image's `__TEXT` is, and each file's mappings say which file holds it.
enum SharedCache {
    private static let folder = URL(filePath: "/System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld")
    #if arch(arm64)
    private static let name = "dyld_shared_cache_arm64e"
    #else
    private static let name = "dyld_shared_cache_x86_64h"
    #endif

    /// Whether the `__TEXT` of the image at `path` holds `text`.
    static func image(_ path: String, holds text: String) throws -> Bool {
        let main = try Data(contentsOf: folder.appending(path: name))
        let table = Int(main.number(UInt64.self, at: 0x88))
        for index in 0..<Int(main.number(UInt64.self, at: 0x90)) {
            let entry = table + index * 32
            guard main.cString(at: Int(main.number(UInt32.self, at: entry + 28))) == path else { continue }
            let address = main.number(UInt64.self, at: entry + 16), size = main.number(UInt32.self, at: entry + 24)
            return try bytes(at: address, size: size).range(of: Data(text.utf8)) != nil
        }
        return false
    }

    private static func bytes(at address: UInt64, size: UInt32) throws -> Data {
        let files = try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false)).filter {
            $0 == name || $0.hasPrefix(name + ".") && !$0.hasSuffix(".map") && !$0.hasSuffix(".atlas")
        }
        for file in files {
            let handle = try FileHandle(forReadingFrom: folder.appending(path: file))
            defer { try? handle.close() }
            let header = try handle.read(upToCount: 24) ?? Data()
            let mappings = Int(header.number(UInt32.self, at: 16)), count = Int(header.number(UInt32.self, at: 20))
            try handle.seek(toOffset: 0)
            let table = try handle.read(upToCount: mappings + count * 32) ?? Data()
            for index in 0..<count {
                let mapping = mappings + index * 32
                let start = table.number(UInt64.self, at: mapping), length = table.number(UInt64.self, at: mapping + 8)
                guard start <= address, address + UInt64(size) <= start + length else { continue }
                try handle.seek(toOffset: table.number(UInt64.self, at: mapping + 16) + address - start)
                return try handle.read(upToCount: Int(size)) ?? Data()
            }
        }
        return Data()
    }
}

private extension Data {
    func number<Number: FixedWidthInteger>(_: Number.Type, at offset: Int) -> Number {
        Number(littleEndian: withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: Number.self) })
    }

    func cString(at offset: Int) -> String {
        String(decoding: self[offset...].prefix { $0 != 0 }, as: UTF8.self)
    }
}
