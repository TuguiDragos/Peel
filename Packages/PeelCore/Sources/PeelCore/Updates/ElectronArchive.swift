import Foundation

/// Reads a file out of an Electron archive (`.asar`) without running anything.
enum ElectronArchive {
    /// The file named `name` at the top of `archive`, or nil.
    static func file(named name: String, in archive: Data) -> Data? {
        func number(at offset: Int) -> Int? {
            guard archive.count >= offset + 4 else { return nil }
            let value = archive.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self) }
            return Int(value.littleEndian)
        }
        guard let indexSize = number(at: 4), let indexLength = number(at: 12), archive.count >= 16 + indexLength,
              let index = try? JSONSerialization.jsonObject(with: archive.subdata(in: 16..<16 + indexLength)),
              let files = (index as? [String: Any])?["files"] as? [String: Any],
              let entry = files[name] as? [String: Any], entry["unpacked"] as? Bool != true,
              let size = entry["size"] as? Int, let offset = (entry["offset"] as? String).flatMap({ Int($0) })
        else { return nil }
        let start = 8 + indexSize + offset
        guard size >= 0, offset >= 0, archive.count >= start + size else { return nil }
        return archive.subdata(in: start..<start + size)
    }
}
