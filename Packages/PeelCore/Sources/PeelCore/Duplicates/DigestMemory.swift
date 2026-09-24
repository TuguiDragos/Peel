import CryptoKit
public import Foundation
import Synchronization

/// Digests one duplicate scan computed, saved so the next scan does not read an unchanged file again. A file is
/// known by its device and inode, its size, and its modification, status change, and creation times, never by
/// its name, and no name is saved. Every write moves the status change time, which cannot be set back, so a file
/// rewritten and given its old dates again is read again.
public struct DigestMemory: Sendable {
    /// The most files remembered, about 12 MB on disk: room for the files of a home folder that share a size with
    /// another file, which are the only ones read. The least recently used are forgotten first.
    public static let maximumFiles = 100_000

    public let url: URL
    let limit: Int

    public init(url: URL = DigestMemory.defaultURL) {
        self.init(url: url, limit: Self.maximumFiles)
    }

    init(url: URL, limit: Int) {
        self.url = url
        self.limit = limit
    }

    public static var defaultURL: URL {
        PeelFolder.url.appending(path: "digests.bin")
    }

    func load(now: Date = .now) -> KnownDigests {
        KnownDigests(entries: FileLock.whileHeld(beside: url) { read() }, day: Self.day(of: now))
    }

    /// Merges what this scan learned into the file's current contents instead of replacing them, since the app
    /// and `peel` can scan at the same time.
    func save(_ known: KnownDigests) {
        let learned = known.learned
        guard !learned.isEmpty else { return }
        FileLock.whileHeld(beside: url) {
            var entries = read()
            entries.merge(learned) { old, new in new.merged(over: old) }
            write(entries)
        }
    }

    private static func day(of date: Date) -> UInt32 {
        UInt32(clamping: Int(date.timeIntervalSinceReferenceDate / 86_400))
    }

    // MARK: The file

    /// The file holds this mark, one record per file, then the SHA-256 of everything before it. The memory only
    /// saves time, so a file that does not match this layout or its checksum is treated as empty, not trusted.
    private static let mark = Array("PeelDigests1".utf8)
    private static let recordLength = 6 * 8 + 2 * 4 + 2 * ContentDigest.byteCount
    private static let hasSample: UInt32 = 1
    private static let hasFull: UInt32 = 2

    private func read() -> [KnownDigests.Key: KnownDigests.Entry] {
        let maximum = Self.mark.count + limit * Self.recordLength + ContentDigest.byteCount
        guard let data = BoundedRead.data(at: url, maximum: maximum) else { return [:] }
        let bytes = [UInt8](data)
        let body = bytes.count - ContentDigest.byteCount
        guard body >= Self.mark.count, (body - Self.mark.count).isMultiple(of: Self.recordLength),
              Array(bytes[..<Self.mark.count]) == Self.mark,
              ContentDigest(SHA256.hash(data: bytes[..<body])).bytes == Array(bytes[body...]) else { return [:] }

        var entries: [KnownDigests.Key: KnownDigests.Entry] = [:]
        entries.reserveCapacity((body - Self.mark.count) / Self.recordLength)
        bytes.withUnsafeBytes { raw in
            var offset = Self.mark.count
            func next<T: FixedWidthInteger>(_: T.Type) -> T {
                defer { offset += MemoryLayout<T>.size }
                return T(littleEndian: raw.loadUnaligned(fromByteOffset: offset, as: T.self))
            }
            func digest() -> ContentDigest {
                defer { offset += ContentDigest.byteCount }
                return ContentDigest(bytes: Array(raw[offset..<(offset + ContentDigest.byteCount)]))!
            }
            while offset < body {
                let key = KnownDigests.Key(
                    device: next(Int64.self), inode: next(UInt64.self), size: next(Int64.self),
                    modificationTime: next(Int64.self), statusChangeTime: next(Int64.self), creationTime: next(Int64.self)
                )
                let lastUsed = next(UInt32.self)
                let parts = next(UInt32.self)
                let sample = digest()
                let full = digest()
                entries[key] = KnownDigests.Entry(
                    sample: parts & Self.hasSample != 0 ? sample : nil,
                    full: parts & Self.hasFull != 0 ? full : nil,
                    lastUsed: lastUsed
                )
            }
        }
        return entries
    }

    private func write(_ entries: [KnownDigests.Key: KnownDigests.Entry]) {
        let kept = entries.count > limit
            ? Array(entries.sorted { $0.value.lastUsed > $1.value.lastUsed }.prefix(limit))
            : Array(entries)
        var bytes = Self.mark
        bytes.reserveCapacity(Self.mark.count + kept.count * Self.recordLength + ContentDigest.byteCount)
        func append<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.littleEndian) { bytes.append(contentsOf: $0) }
        }
        let none = [UInt8](repeating: 0, count: ContentDigest.byteCount)
        for (key, entry) in kept {
            for number in [key.device, Int64(bitPattern: key.inode), key.size, key.modificationTime, key.statusChangeTime, key.creationTime] {
                append(number)
            }
            append(entry.lastUsed)
            append((entry.sample == nil ? 0 : Self.hasSample) | (entry.full == nil ? 0 : Self.hasFull))
            bytes += entry.sample?.bytes ?? none
            bytes += entry.full?.bytes ?? none
        }
        bytes += ContentDigest(SHA256.hash(data: bytes)).bytes
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data(bytes).write(to: url, options: .atomic)
    }
}

/// The digest memory during one scan, looked up and added to by reads that run in parallel.
final class KnownDigests: Sendable {
    struct Key: Hashable {
        let device: Int64
        let inode: UInt64
        let size: Int64
        let modificationTime: Int64
        let statusChangeTime: Int64
        let creationTime: Int64

        init(device: Int64, inode: UInt64, size: Int64, modificationTime: Int64, statusChangeTime: Int64, creationTime: Int64) {
            self.device = device
            self.inode = inode
            self.size = size
            self.modificationTime = modificationTime
            self.statusChangeTime = statusChangeTime
            self.creationTime = creationTime
        }

        init(_ identity: FileIdentity) {
            self.init(
                device: Int64(identity.link.device), inode: UInt64(identity.link.inode), size: identity.size,
                modificationTime: Int64(identity.modificationTime), statusChangeTime: Int64(identity.statusChangeTime),
                creationTime: Int64(identity.creationTime)
            )
        }
    }

    struct Entry {
        var sample: ContentDigest?
        var full: ContentDigest?
        var lastUsed: UInt32

        func merged(over older: Entry) -> Entry {
            Entry(sample: sample ?? older.sample, full: full ?? older.full, lastUsed: max(lastUsed, older.lastUsed))
        }
    }

    private struct State {
        var entries: [Key: Entry]
        var changed: Set<Key> = []
    }

    private let state: Mutex<State>
    private let day: UInt32

    init(entries: [Key: Entry], day: UInt32) {
        state = Mutex(State(entries: entries))
        self.day = day
    }

    func sample(of identity: FileIdentity) -> ContentDigest? {
        known(identity) { $0.sample }
    }

    func full(of identity: FileIdentity) -> ContentDigest? {
        known(identity) { $0.full }
    }

    func keep(sample: ContentDigest, of identity: FileIdentity) {
        change(identity) { $0.sample = sample }
    }

    func keep(full: ContentDigest, of identity: FileIdentity) {
        change(identity) { $0.full = full }
    }

    /// The entries this scan added or used. Saving only these never overwrites newer entries that another scan
    /// saved in the meantime.
    var learned: [Key: Entry] {
        state.withLock { state in
            Dictionary(uniqueKeysWithValues: state.changed.compactMap { key in state.entries[key].map { (key, $0) } })
        }
    }

    private func known(_ identity: FileIdentity, _ part: (Entry) -> ContentDigest?) -> ContentDigest? {
        let key = Key(identity)
        return state.withLock { state in
            guard var entry = state.entries[key], let digest = part(entry) else { return nil }
            if entry.lastUsed != day {
                entry.lastUsed = day
                state.entries[key] = entry
                state.changed.insert(key)
            }
            return digest
        }
    }

    private func change(_ identity: FileIdentity, _ update: (inout Entry) -> Void) {
        let key = Key(identity)
        state.withLock { state in
            var entry = state.entries[key] ?? Entry(lastUsed: day)
            update(&entry)
            entry.lastUsed = day
            state.entries[key] = entry
            state.changed.insert(key)
        }
    }
}
