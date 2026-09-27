import Darwin
import Foundation
internal import PeelPrivileged

/// What a removal moved, written down item by item as it moves, beside History. History takes each item over once
/// it records it; what a process that stopped before then left here goes into History the next time History is read,
/// as an interrupted removal, so nothing Peel moved to the Trash is ever missing from it.
struct RemovalJournal: Sendable {
    /// The process that wrote a line: its id, and when it started, since macOS gives an ended process's id to a new
    /// one.
    struct Writer: Sendable, Codable, Hashable {
        let pid: Int32
        let started: Double

        static let current = Writer(pid: getpid(), started: startTime(of: getpid()) ?? 0)

        /// Whether the process that wrote the line still runs, and so will record the line itself.
        var isRunning: Bool {
            self == .current || Self.startTime(of: pid) == started
        }

        private static func startTime(of pid: Int32) -> Double? {
            var info = proc_bsdinfo()
            let size = Int32(MemoryLayout<proc_bsdinfo>.size)
            guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
            return Double(info.pbi_start_tvsec) + Double(info.pbi_start_tvusec) / 1_000_000
        }
    }

    /// One item that moved.
    struct Entry: Sendable, Codable, Hashable {
        let writer: Writer
        /// The move it was part of, so an interrupted one comes back as one entry of History.
        let batch: UUID
        let item: TrashedItem

        /// History's record of the item, when the removal stopped before it recorded the item in its own words.
        /// It names no tool, since which tool moved the item is not known.
        var interruptedRecord: RemovalRecord {
            RemovalRecord(batch: batch, item: item, size: nil, source: "Interrupted removal", sourceKey: "interrupted", tool: "")
        }
    }

    /// An item as History keeps it: where it was, where it went, and when, to the millisecond. It is the same
    /// for an item in memory and for that item read back from a file, which keeps its time to the millisecond.
    struct Key: Hashable {
        let originalURL: URL
        let trashedURL: URL
        let time: String

        init(_ item: TrashedItem) {
            originalURL = item.originalURL
            trashedURL = item.trashedURL
            time = LogTime.text(for: item.date)
        }
    }

    let url: URL

    /// The journal beside the History log at `history`.
    init(beside history: URL) {
        url = history.deletingLastPathComponent().appending(path: "removals.journal")
    }

    /// Writes down `items`, which moved together in `batch`, one line each. An item the journal was in, Peel's own
    /// folder as Peel removes itself, is left out: History went with it, and writing the line would make the
    /// folder again.
    func note(_ items: [TrashedItem], batch: UUID, by writer: Writer = .current) {
        let journal = url.path(percentEncoded: false)
        let lines = items
            .filter { !PathComponents.isPath(journal, atOrInside: $0.originalURL.path(percentEncoded: false)) }
            .compactMap { item in (try? Self.encoder.encode(Entry(writer: writer, batch: batch, item: item))) }
        guard !lines.isEmpty else { return }
        FileLock.whileHeld(beside: url) {
            let descriptor = open(journal, O_RDWR | O_APPEND | O_CREAT | O_CLOEXEC, 0o600)
            guard descriptor >= 0 else { return }
            defer { close(descriptor) }
            var data = Data()
            // A line cut short, as when the disk filled up, is ended first, so the next line is not read as part
            // of it.
            let end = lseek(descriptor, 0, SEEK_END)
            var last: UInt8 = 0
            if end > 0, pread(descriptor, &last, 1, end - 1) == 1, last != UInt8(ascii: "\n") {
                data.append(UInt8(ascii: "\n"))
            }
            for line in lines {
                data += line + Data("\n".utf8)
            }
            _ = data.withUnsafeBytes { Darwin.write(descriptor, $0.baseAddress, $0.count) }
        }
    }

    /// Every line the journal holds. A line that does not decode is left out. Reading makes nothing on the disk:
    /// with no journal there is nothing to take in.
    func entries() -> [Entry] {
        guard !url.isMissing else { return [] }
        return FileLock.whileHeld(beside: url) { read() }
    }

    /// The lines of processes that no longer run.
    func left() -> [Entry] {
        let entries = entries()
        let running = Set(entries.map(\.writer)).filter(\.isRunning)
        return entries.filter { !running.contains($0.writer) }
    }

    /// Takes out the lines of `items`, which History now has.
    func forget(_ items: [TrashedItem]) {
        let keys = Set(items.map(Key.init))
        forget { keys.contains(Key($0.item)) }
    }

    /// Takes out `entries`.
    func forget(_ entries: Set<Entry>) {
        forget { entries.contains($0) }
    }

    private func forget(where isForgotten: (Entry) -> Bool) {
        guard !url.isMissing else { return }
        FileLock.whileHeld(beside: url) {
            let entries = read()
            let kept = entries.filter { !isForgotten($0) }
            guard kept.count != entries.count else { return }
            let data = kept.compactMap { try? Self.encoder.encode($0) }.reduce(into: Data()) { $0 += $1 + Data("\n".utf8) }
            try? data.write(to: url, options: .atomic)
        }
    }

    private func read() -> [Entry] {
        guard let data = BoundedRead.data(at: url, maximum: 64 * 1_024 * 1_024) else { return [] }
        return data.split(separator: UInt8(ascii: "\n")).compactMap { try? Self.decoder.decode(Entry.self, from: $0) }
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = LogTime.encoding
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = LogTime.decoding
        return decoder
    }()
}
