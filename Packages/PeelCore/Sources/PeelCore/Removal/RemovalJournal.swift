import Darwin
public import Foundation
internal import PeelPrivileged

/// The removal of History a move goes into, and its part, for a removal recorded a part at a time. The journal keeps
/// it with each item, so what a part left there when its process stopped joins that removal under the part's name.
public struct RecordedRemoval: Sendable {
    public let batch: UUID
    public let part: RemovalPart
    /// What the page measured of each item, and the items that share most of their storage, as History records them.
    public let sizes: [URL: Int64]
    public let sharingStorage: Set<URL>

    public init(batch: UUID, part: RemovalPart, sizes: [URL: Int64] = [:], sharingStorage: Set<URL> = []) {
        self.batch = batch
        self.part = part
        self.sizes = sizes
        self.sharingStorage = sharingStorage
    }

    /// The removal the moves in the current task go into, set by whoever records them.
    @TaskLocal public static var current: RecordedRemoval?

    /// The same removal, with the sizes of `more` known too.
    public func measuring(_ more: [URL: Int64]) -> RecordedRemoval {
        RecordedRemoval(
            batch: batch, part: part, sizes: sizes.merging(more) { _, new in new }, sharingStorage: sharingStorage
        )
    }
}

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
        var item: TrashedItem
        /// The record History couldn't take, kept here so the item comes back as what it was.
        var record: RemovalRecord? = nil
        /// The part of the removal the item moved in, when the removal was recorded a part at a time.
        var part: RemovalPart? = nil
        /// The disk the item moved on, read then: that disk may be gone when the line is taken in.
        var disk: TrashedDisk? = nil
        var size: Int64? = nil
        var sharedStorage: Bool? = nil
        /// Whether the line was written before the item moved: it names the Trash the item goes to, not where it
        /// landed, and stands for the item until the line written once it moved.
        var isBeforeTheMove: Bool? = nil

        /// History's record of the item: the one kept here, or else one of its part, with the size its page measured,
        /// or else that of an interrupted removal, which names no tool, since which tool moved the item is not known.
        var recordToTakeIn: RemovalRecord {
            if let record { return record }
            let part = part ?? RemovalPart(source: "Interrupted removal", sourceKey: "interrupted", tool: "")
            return RemovalRecord(
                batch: batch, item: item, size: size, source: part.source, sourceKey: part.sourceKey, tool: part.tool,
                sharedStorage: sharedStorage, disk: disk
            )
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
    /// The History log that takes in what the journal holds.
    let history: URL

    /// The journal beside the History log at `history`.
    init(beside history: URL) {
        url = history.deletingLastPathComponent().appending(path: "removals.journal")
        self.history = history
    }

    /// Why a line can't be written here, or nil when it can: there is no journal yet, or it opens as the file it should
    /// be and this account can write it.
    var writeProblem: HistoryWriteProblem? {
        if url.isMissing { return nil }
        guard canBeRead else { return .journalUnreadable(url) }
        return access(url.path(percentEncoded: false), W_OK) == 0 ? nil : .journalNotWritable(url)
    }

    /// Whether something stands where the journal goes that doesn't open as one, which is kept aside.
    var isUnreadable: Bool {
        !url.isMissing && !canBeRead
    }

    private var canBeRead: Bool {
        BoundedRead.opens(url, maximum: Self.maximumBytes)
    }

    /// Keeps a journal that can't be read beside a new one, under another name, and answers that name: while it stands
    /// in its place, what a removal cut short leaves behind would be lost.
    func setAsideIfUnreadable() -> URL? {
        guard isUnreadable else { return nil }
        return DamagedFile.setAside(url)
    }

    /// Whether History can be read, and so take in what is written here.
    var historyCanBeRead: Bool {
        RemovalLog.canBeRead(at: history)
    }

    var historyWriteProblem: HistoryWriteProblem? {
        RemovalLog.writeProblem(at: history)
    }

    /// Writes down `items`, which move together in `batch`, or in the removal and part `recorded` names, one line
    /// each, and answers whether every line was written. With `beforeTheMove`, the items have yet to move, and each
    /// names the Trash it goes to. An item the journal was in, Peel's own folder as Peel removes itself, is left out:
    /// History went with it, and writing the line would make the folder again.
    @discardableResult
    func note(
        _ items: [TrashedItem], batch: UUID, recordedAs recorded: RecordedRemoval? = .current,
        beforeTheMove: Bool = false, by writer: Writer = .current
    ) -> Bool {
        let journal = url.path(percentEncoded: false)
        let entry = { (item: TrashedItem) in
            Entry(
                writer: writer, batch: recorded?.batch ?? batch, item: item, part: recorded?.part,
                disk: beforeTheMove ? TrashedDisk(leaving: item) : TrashedDisk(of: item),
                size: recorded?.sizes[item.originalURL],
                sharedStorage: recorded?.sharingStorage.contains(item.originalURL) == true ? true : nil,
                isBeforeTheMove: beforeTheMove ? true : nil
            )
        }
        guard let lines = try? items
            .filter({ !PathComponents.isPath(journal, atOrInside: $0.originalURL.path(percentEncoded: false)) })
            .map({ try Self.encoder.encode(entry($0)) })
        else { return false }
        guard !lines.isEmpty else { return true }
        return FileLock.whileHeld(beside: url) {
            let opened = PeelFolder.whileOpen(making: url.deletingLastPathComponent()) {
                open(journal, O_RDWR | O_APPEND | O_CREAT | O_CLOEXEC, 0o600)
            }
            guard let descriptor = opened, descriptor >= 0 else { return false }
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
            let wrote = data.withUnsafeBytes { Darwin.write(descriptor, $0.baseAddress, $0.count) } == data.count
            guard wrote, beforeTheMove else { return wrote }
            return Self.flush(descriptor, before: items)
        }
    }

    /// Puts the lines just written on `descriptor` ahead of the moves they announce: a move must not reach a drive
    /// before its line. An item on another drive than the journal's waits until the line is on its drive.
    private static func flush(_ descriptor: Int32, before items: [TrashedItem]) -> Bool {
        var journal = stat()
        let acrossDrives = fstat(descriptor, &journal) != 0 || items.contains { item in
            var info = stat()
            return lstat(item.originalURL.path(percentEncoded: false), &info) != 0 || info.st_dev != journal.st_dev
        }
        if let flushStandIn { return flushStandIn(acrossDrives) }
        return DriveFlush.ahead(of: descriptor, acrossDrives: acrossDrives)
    }

    /// For a test: a power cut can't be made on demand.
    @TaskLocal static var flushStandIn: (@Sendable (_ acrossDrives: Bool) -> Bool)?

    /// Every line the journal holds. A line that does not decode is left out. Reading makes nothing on the disk:
    /// with no journal there is nothing to take in.
    func entries() -> [Entry] {
        guard !url.isMissing else { return [] }
        return FileLock.whileHeld(beside: url) { read() }
    }

    /// What the lines of processes that no longer run come to: what was written once it moved, what a line written
    /// before a move with none after it settles to on the disk (`settled`), and the lines History lets go once it has
    /// them. Such a line of an item whose Trash is on a disk that isn't connected stays for later.
    struct Left {
        var written: [Entry] = []
        var settled: [Entry] = []
        var lines: Set<Entry> = []
    }

    func left() -> Left {
        let entries = entries()
        let running = Set(entries.map(\.writer)).filter(\.isRunning)
        let stopped = entries.filter { !running.contains($0.writer) }
        let moved = Set(stopped.filter { $0.isBeforeTheMove != true }.map(Departure.init))
        let mounted = MountedDisks.now()
        var left = Left()
        for entry in stopped {
            if entry.isBeforeTheMove != true {
                left.written.append(entry)
            } else if !moved.contains(Departure(entry)) {
                switch Self.landing(of: entry, on: mounted) {
                case .inTheTrash(let item):
                    var landed = entry
                    landed.item = item
                    landed.disk = TrashedDisk(of: item)
                    landed.isBeforeTheMove = nil
                    left.settled.append(landed)
                case .notKnownYet: continue
                case .nowhere: break
                }
            }
            left.lines.insert(entry)
        }
        return left
    }

    /// Where the items moving now have landed, among `entries`: an item whose line was written before its move, with
    /// none after it yet, found in its Trash by its identity. Whoever watches the Trash asks this between a rename and
    /// the line written after it.
    func landedBeforeTheirLine(among entries: [Entry]) -> [TrashedItem] {
        let moved = Set(entries.filter { $0.isBeforeTheMove != true }.map(Departure.init))
        let waiting = entries.filter { $0.isBeforeTheMove == true && !moved.contains(Departure($0)) }
        guard !waiting.isEmpty else { return [] }
        let mounted = MountedDisks.now()
        return waiting.compactMap { entry in
            guard case .inTheTrash(let item) = Self.landing(of: entry, on: mounted) else { return nil }
            return item
        }
    }

    /// Where an item that was about to move is: in its Trash, under a name the move gives one, with both its places
    /// where its disk is mounted now, nowhere this line can account for (still in its place, gone from the Trash, or
    /// with no identity to know it by), or not known yet while that Trash's disk isn't connected.
    private enum Landing {
        case inTheTrash(TrashedItem)
        case nowhere
        case notKnownYet
    }

    private static func landing(of entry: Entry, on mounted: MountedDisks) -> Landing {
        let record = entry.recordToTakeIn
        guard let identity = record.trashedItem.identity else { return .nowhere }
        guard record.isOnAConnectedDisk(mounted) else { return .notKnownYet }
        let item = record.located(on: mounted).trashedItem
        var info = stat()
        if lstat(item.originalURL.path(percentEncoded: false), &info) == 0, identity.isTheItem(info) { return .nowhere }
        let trash = item.trashedURL.deletingLastPathComponent()
        let found = TrashService.item(
            named: item.originalURL.lastPathComponent, inode: identity.inode, in: trash, where: identity.isTheItem
        )
        return found.map {
            .inTheTrash(TrashedItem(originalURL: item.originalURL, trashedURL: $0, date: item.date, identity: identity))
        } ?? .nowhere
    }

    /// An item leaving its place in one removal, by the process that moved it, which its two lines share.
    private struct Departure: Hashable {
        let writer: Writer
        let batch: UUID
        let originalURL: URL

        init(_ entry: Entry) {
            writer = entry.writer
            batch = entry.batch
            originalURL = entry.item.originalURL
        }
    }

    /// Takes out the lines of `items`, which History now has, and the lines this process wrote before they moved.
    func forget(_ items: [TrashedItem]) {
        let keys = Set(items.map(Key.init))
        let places = Set(items.map(\.originalURL))
        forget { entry in
            keys.contains(Key(entry.item))
                || entry.isBeforeTheMove == true && entry.writer == .current && places.contains(entry.item.originalURL)
        }
    }

    /// Takes out `entries`.
    func forget(_ entries: Set<Entry>) {
        forget { entries.contains($0) }
    }

    /// Keeps with each item's line the record History couldn't write.
    func keep(_ records: [RemovalRecord]) {
        let byItem = Dictionary(records.map { (Key($0.trashedItem), $0) }, uniquingKeysWith: { first, _ in first })
        guard !url.isMissing else { return }
        FileLock.whileHeld(beside: url) {
            var entries = read()
            var changed = false
            for index in entries.indices {
                guard let record = byItem[Key(entries[index].item)] else { continue }
                entries[index].record = record
                changed = true
            }
            guard changed else { return }
            write(entries)
        }
    }

    private func forget(where isForgotten: (Entry) -> Bool) {
        guard !url.isMissing else { return }
        FileLock.whileHeld(beside: url) {
            let entries = read()
            let kept = entries.filter { !isForgotten($0) }
            guard kept.count != entries.count else { return }
            write(kept)
        }
    }

    func write(_ entries: [Entry]) {
        let data = entries.compactMap { try? Self.encoder.encode($0) }.reduce(into: Data()) { $0 += $1 + Data("\n".utf8) }
        try? PeelFolder.write(data, to: url)
    }

    private func read() -> [Entry] {
        guard let data = BoundedRead.data(at: url, maximum: Self.maximumBytes) else { return [] }
        return data.split(separator: UInt8(ascii: "\n")).compactMap { try? Self.decoder.decode(Entry.self, from: $0) }
    }

    private static let maximumBytes = 64 * 1_024 * 1_024

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
