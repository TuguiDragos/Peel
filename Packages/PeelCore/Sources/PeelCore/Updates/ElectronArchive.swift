import Foundation

/// Reads a file out of an Electron archive (`.asar`) without running anything.
enum ElectronArchive {
    /// The file named `name` at the top of `archive`, or nil. The archive's own sizes and places are never believed.
    static func file(named name: String, in archive: Data) -> Data? {
        func number(at offset: Int) -> Int? {
            guard archive.count >= offset + 4 else { return nil }
            let value = archive.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self) }
            return Int(value.littleEndian)
        }
        func bytes(from offset: Int, count: Int) -> Data? {
            guard offset >= 0, count >= 0, offset <= archive.count, count <= archive.count - offset else { return nil }
            return archive.dropFirst(offset).prefix(count)
        }
        guard let indexSize = number(at: 4), let indexLength = number(at: 12),
              let json = bytes(from: 16, count: indexLength),
              let index = try? JSONSerialization.jsonObject(with: json),
              let files = (index as? [String: Any])?["files"] as? [String: Any],
              let entry = files[name] as? [String: Any], entry["unpacked"] as? Bool != true,
              let size = entry["size"] as? Int, let offset = (entry["offset"] as? String).flatMap({ Int($0) }),
              offset >= 0, offset <= archive.count
        else { return nil }
        return bytes(from: 8 + indexSize + offset, count: size).map { Data($0) }
    }
}
