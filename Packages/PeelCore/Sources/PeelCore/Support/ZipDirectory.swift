import Foundation

/// Reads the names a ZIP archive lists without extracting anything, from the central directory at the end of
/// the file: the end record, or the ZIP64 records an archive past 4 GB or 65,535 entries keeps instead. Nil for
/// an archive that cannot be read in full.
enum ZipDirectory {
    /// 64 MB: far more than the directory of an app's archive needs, while capping what an untrusted file can
    /// make Peel read.
    static let largestDirectory = 64 * 1_048_576
    static let mostEntries = 500_000

    private static let endRecord: UInt32 = 0x0605_4b50
    private static let zip64Locator: UInt32 = 0x0706_4b50
    private static let zip64EndRecord: UInt32 = 0x0606_4b50
    private static let directoryEntry: UInt32 = 0x0201_4b50

    static func names(at url: URL) -> [String]? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd(), size >= 22 else { return nil }
        // The end record is 22 bytes, and a comment of up to 65,535 bytes may follow it.
        let tailLength = min(size, 22 + 65_535)
        let tailStart = size - tailLength
        guard let tail = read(handle, at: tailStart, count: Int(tailLength)),
              let end = tail.lastIndex(of: endRecord, from: tail.count - 22) else { return nil }
        var entries = UInt64(tail.number(UInt16.self, at: end + 10))
        var directorySize = UInt64(tail.number(UInt32.self, at: end + 12))
        var directoryOffset = UInt64(tail.number(UInt32.self, at: end + 16))
        if entries == 0xFFFF || directorySize == 0xFFFF_FFFF || directoryOffset == 0xFFFF_FFFF {
            let locator = Int64(tailStart) + Int64(end) - 20
            guard locator >= 0, let located = read(handle, at: UInt64(locator), count: 20), located.number(UInt32.self, at: 0) == zip64Locator,
                  let record = read(handle, at: located.number(UInt64.self, at: 8), count: 56),
                  record.number(UInt32.self, at: 0) == zip64EndRecord else { return nil }
            entries = record.number(UInt64.self, at: 32)
            directorySize = record.number(UInt64.self, at: 40)
            directoryOffset = record.number(UInt64.self, at: 48)
        }
        guard entries <= UInt64(mostEntries), directorySize <= UInt64(largestDirectory),
              directoryOffset <= size, directorySize <= size - directoryOffset,
              let directory = read(handle, at: directoryOffset, count: Int(directorySize)) else { return nil }

        var names: [String] = []
        var offset = 0
        for _ in 0..<entries {
            guard offset + 46 <= directory.count, directory.number(UInt32.self, at: offset) == directoryEntry else { return nil }
            let nameLength = Int(directory.number(UInt16.self, at: offset + 28))
            let extraLength = Int(directory.number(UInt16.self, at: offset + 30))
            let commentLength = Int(directory.number(UInt16.self, at: offset + 32))
            guard offset + 46 + nameLength <= directory.count else { return nil }
            names.append(String(decoding: directory[(offset + 46)..<(offset + 46 + nameLength)], as: UTF8.self))
            offset += 46 + nameLength + extraLength + commentLength
        }
        return names
    }

    private static func read(_ handle: FileHandle, at offset: UInt64, count: Int) -> [UInt8]? {
        guard (try? handle.seek(toOffset: offset)) != nil,
              let data = try? handle.read(upToCount: count), data.count == count else { return nil }
        return [UInt8](data)
    }
}

private extension [UInt8] {
    /// Reads the number at `offset`, little-endian like every number in the format.
    func number<Number: FixedWidthInteger>(_: Number.Type, at offset: Int) -> Number {
        (0..<MemoryLayout<Number>.size).reduce(Number.zero) { $0 | Number(self[offset + $1]) << (8 * $1) }
    }

    func lastIndex(of signature: UInt32, from start: Int) -> Int? {
        var index = start
        while index >= 0 {
            if number(UInt32.self, at: index) == signature { return index }
            index -= 1
        }
        return nil
    }
}
