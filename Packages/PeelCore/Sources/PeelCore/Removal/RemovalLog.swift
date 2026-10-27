public import Foundation
internal import PeelPrivileged

/// A problem reading or writing the log, for History to show.
public enum RemovalLogProblem: Sendable, Equatable {
    /// The file could not be decoded. It was set aside under this name, and a new log was started with the rows
    /// that could be read.
    case damaged(setAside: URL)
    /// The file could not be read or set aside, so nothing new is being recorded.
    case unreadable
    /// The log could not be written, so the last removal is not recorded.
    case couldNotRecord
    /// The log could not be written after a Put Back or a Forget, so it still lists those records.
    case couldNotUpdate
}

/// The result of reading or changing the log. `records` is nil when the file was left
/// untouched, so the caller keeps whatever it already has on screen.
public struct RemovalLogOutcome: Sendable {
    public let records: [RemovalRecord]?
    public let problem: RemovalLogProblem?
    /// How many older removals the log no longer lists, as the totals count them.
    public let noLongerListed: Int
}

/// The record of everything Peel moved to the Trash, so History can put it back.
///
/// An actor because every change is a read-modify-write of one file: two removals at once
/// would otherwise overwrite each other. None of its methods suspend once they start, so
/// actor reentrancy cannot interleave two of them.
public actor RemovalLog {
    /// The most records the file keeps. Past this, the oldest batches are dropped whole, never in part.
    public static let maximumRecords = 20_000
    /// The largest file read as History, since any process of the user can rewrite it. Peel never writes more:
    /// records with long paths take several times what short ones do, and the oldest removals go first.
    static let maximumBytes = 64 * 1_024 * 1_024

    public nonisolated let url: URL
    public private(set) var problem: RemovalLogProblem?
    /// The records last read from the file or written to it, and the file they are in. A read of the same file,
    /// unchanged, takes them instead of decoding it again; a write by any other process changes the file.
    private var kept: (file: FileIdentity, records: [RemovalRecord])?
    /// What removals moved and have not recorded yet, item by item.
    private let journal: RemovalJournal
    private let totals: URL
    private let flush: @Sendable (String) -> Bool
    private let readLimit: Int

    public init(url: URL = RemovalHistory.defaultURL) {
        self.init(url: url, flush: DriveFlush.file(at:))
    }

    init(url: URL, flush: @escaping @Sendable (String) -> Bool, readLimit: Int = maximumBytes) {
        self.url = url
        journal = RemovalJournal(beside: url)
        totals = RemovalTotals.url(beside: url)
        self.flush = flush
        self.readLimit = readLimit
    }

    /// Reads the log. The read takes the lock too, because reading a damaged file sets it aside and writes back
    /// the rows that could be read.
    public func load() -> RemovalLogOutcome {
        whileNoOtherProcessWrites { outcome(current()) }
    }

    /// The places in the Trash where an item Peel moved still is, whichever process moved it: what History records
    /// and what a removal under way has written down so far. Spelled as `PathPattern.comparablePath` spells them.
    public func placesInTheTrash() -> Set<String> {
        let items = (load().records ?? []).map(\.trashedItem) + journal.entries().map(\.item)
        return Set(items.filter(\.isInTheTrash).map { PathPattern.comparablePath(of: $0.trashedURL) })
    }

    public func add(_ records: [RemovalRecord]) -> RemovalLogOutcome {
        whileNoOtherProcessWrites {
            guard !records.isEmpty else { return outcome(current()) }
            guard let existing = current() else { return outcome(nil) }
            let new = Set(records.map(\.batch))
            guard let updated = write(existing + records, keeping: new, orNote: .couldNotRecord) else {
                journal.keep(records)
                return outcome(nil)
            }
            RemovalTotals.change(at: totals) { $0.add(records) }
            // The journal is what records these items if History is lost, so it lets them go only once History is on
            // the drive.
            if flush(url.path(percentEncoded: false)) {
                journal.forget(records.map(\.trashedItem))
            }
            // A removal that is recorded clears an earlier `.couldNotRecord`.
            if problem == .couldNotRecord { problem = nil }
            return outcome(updated)
        }
    }

    /// Adds totals the app kept before `peel` counted too. False when they could not be written.
    public func takeIn(_ earlier: RemovalTotals) -> Bool {
        whileNoOtherProcessWrites { RemovalTotals.change(at: totals) { $0.takeIn(earlier) } }
    }

    /// How many of `urls`, moved in one removal, History can keep and still read back: at most `maximumRecords`, and
    /// fewer when their paths are long. A removal of more is refused before anything moves, since History would lose
    /// it at the next removal, or could no longer read itself.
    public static func mostAtOnce(of urls: [URL]) -> Int {
        let room = maximumBytes / 10 * 9
        var written = 0
        var count = 0
        for url in urls.prefix(maximumRecords) {
            written += estimatedRecordSize(of: url)
            guard written <= room else { break }
            count += 1
        }
        return count
    }

    /// No less than History writes for an item that was at `url`: a kilobyte for the record's own fields, and the
    /// path three times (where it was, where it went, its place on another disk), as JSON writes a URL, with every
    /// slash escaped.
    static func estimatedRecordSize(of url: URL) -> Int {
        1_024 + 3 * url.absoluteString.utf8.reduce(0) { $0 + ($1 == UInt8(ascii: "/") ? 2 : 1) }
    }

    /// Whether History at `url` can be read, known without reading it: it is not there yet, or it opens as the file
    /// it should be. A History that cannot be read is never written over, and nothing moves meanwhile.
    public static func canBeRead(at url: URL = RemovalHistory.defaultURL) -> Bool {
        url.isMissing || BoundedRead.opens(url, maximum: maximumBytes)
    }

    /// Whether a removal could be recorded in History at `url` now: the folder it is written into can be written, and
    /// its disk has room for the copy a safe write makes of the whole file, with a megabyte to spare.
    public static func canBeWritten(
        at url: URL = RemovalHistory.defaultURL,
        freeSpace: (URL) -> UInt64? = RemovalLog.freeSpace(at:)
    ) -> Bool {
        var folder = url.deletingLastPathComponent()
        while folder.isMissing, folder.path(percentEncoded: false) != "/" { folder = folder.deletingLastPathComponent() }
        guard access(folder.path(percentEncoded: false), W_OK) == 0, let free = freeSpace(folder) else { return false }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map { UInt64($0) } ?? 0
        return free >= size + 1_000_000
    }

    /// The space free on the disk holding `folder`, as `statfs(2)` gives it.
    public static func freeSpace(at folder: URL) -> UInt64? {
        var info = statfs()
        guard statfs(folder.path(percentEncoded: false), &info) == 0 else { return nil }
        return UInt64(info.f_bavail) * UInt64(info.f_bsize)
    }

    /// Keeps a History that cannot be read beside the new one, under another name, and starts recording again.
    public func startOver() -> StartOver {
        whileNoOtherProcessWrites {
            guard stored() == nil else { return .notNeeded }
            guard DamagedFile.setAside(url) != nil else { return .couldNotSetAside }
            problem = nil
            return .started
        }
    }

    public func remove(_ ids: Set<UUID>) -> RemovalLogOutcome {
        whileNoOtherProcessWrites {
            guard let existing = current() else { return outcome(nil) }
            let updated = existing.filter { !ids.contains($0.id) }
            return outcome(write(updated, orNote: .couldNotUpdate))
        }
    }

    /// What a read or change of the log answers, once it has `records` or left the file untouched (nil).
    private func outcome(_ records: [RemovalRecord]?) -> RemovalLogOutcome {
        RemovalLogOutcome(
            records: records, problem: problem, noLongerListed: RemovalTotals.read(beside: url).noLongerListed
        )
    }

    /// Runs `change` under a file lock. The app and `peel` both write this log, and the actor keeps order only
    /// inside one process.
    private func whileNoOtherProcessWrites<T>(_ change: () -> T) -> T {
        FileLock.whileHeld(beside: url, change)
    }

    /// Sets `problem`, or clears it when a read went well (nil). A good read leaves two problems in place. A
    /// damaged file stays reported, because the copy set aside is the only trace of it. `.couldNotRecord` stays
    /// until a removal is recorded: History opens by reading the older, healthy file, and that read would
    /// otherwise clear the notice before the user sees it.
    private func note(_ problem: RemovalLogProblem?) {
        if problem == nil {
            if case .damaged = self.problem { return }
            if self.problem == .couldNotRecord { return }
        }
        self.problem = problem
    }

    /// The records on disk with every removal that stopped before recording itself taken in, or nil when the file
    /// must not be replaced because it could not be read.
    private func current() -> [RemovalRecord]? {
        guard let records = stored() else { return nil }
        return takingInInterrupted(records)
    }

    /// Records what the journal holds for processes that no longer run, as interrupted removals, then lets those
    /// lines go. An item History already has is not recorded again: a process may have stopped after writing
    /// History and before letting its lines go.
    private func takingInInterrupted(_ records: [RemovalRecord]) -> [RemovalRecord] {
        let left = journal.left()
        guard !left.isEmpty else { return records }
        let recorded = Set(records.map { RemovalJournal.Key($0.trashedItem) })
        let interrupted = left.filter { !recorded.contains(RemovalJournal.Key($0.item)) }.map(\.recordToTakeIn)
        var updated = records
        if !interrupted.isEmpty {
            let taken = Set(interrupted.map(\.batch))
            guard let written = write(records + interrupted, keeping: taken, orNote: .couldNotRecord) else {
                return records
            }
            updated = written
            RemovalTotals.change(at: totals) { $0.add(interrupted) }
        }
        journal.forget(Set(left))
        return updated
    }

    /// The records on disk, or nil when the file must not be replaced because it could not be read.
    private func stored() -> [RemovalRecord]? {
        guard !url.isMissing else {
            note(nil)
            return []
        }
        if let kept, FileIdentity.of(url) == kept.file {
            note(nil)
            return kept.records
        }
        guard let read = BoundedRead.contents(at: url, maximum: readLimit) else {
            note(.unreadable)
            return nil
        }
        let data = read.data
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = LogTime.decoding
        if let records = try? decoder.decode([RemovalRecord].self, from: data) {
            note(nil)
            kept = (read.file, records)
            return records
        }
        // A row this version cannot read (written by a later version, or broken by hand) must not cost the rest.
        let readable = (try? decoder.decode([Row].self, from: data))?.compactMap(\.record) ?? []
        guard let setAside = DamagedFile.setAside(url) else {
            note(.unreadable)
            return nil
        }
        note(.damaged(setAside: setAside))
        guard !readable.isEmpty, let written = write(readable, orNote: .damaged(setAside: setAside)) else { return [] }
        return written
    }

    /// A row of the file. `record` is nil when the row does not decode.
    private struct Row: Decodable {
        let record: RemovalRecord?

        init(from decoder: any Decoder) {
            record = try? RemovalRecord(from: decoder)
        }
    }

    /// Writes `records`, less the oldest removals beyond `maximumRecords` or what is read back, never one in
    /// `protected`, counts those it left out in the totals, and answers what it wrote, or nil when it couldn't.
    private func write(
        _ records: [RemovalRecord], keeping protected: Set<UUID> = [], orNote failure: RemovalLogProblem
    ) -> [RemovalRecord]? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = LogTime.encoding
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let fitted = try Batches.fitting(
                Self.trimmed(records, keeping: protected), within: readLimit, batch: \.batch, date: \.date,
                keeping: protected, encode: { try encoder.encode($0) }
            )
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            // `.atomic` writes a temporary file and renames it, so a crash leaves either the old log or the new one.
            try fitted.data.write(to: url, options: .atomic)
            // Every writer takes the lock, so the file here is the one just written.
            kept = FileIdentity.of(url).map { ($0, fitted.records) }
            if fitted.records.count < records.count {
                let leftOut = Set(records.map(\.batch)).subtracting(fitted.records.map(\.batch)).count
                RemovalTotals.change(at: totals) { $0.countNoLongerListed(leftOut) }
            }
            return fitted.records
        } catch {
            // An unrecorded removal is the most serious problem, so a later failure never replaces it.
            if problem != .couldNotRecord { note(failure) }
            return nil
        }
    }

    /// Sorts `records` newest first and drops the oldest batches beyond `maximumRecords`, so the file stays quick
    /// to read. A batch is dropped whole, and never one in `protected`: a removal is recorded completely or not
    /// at all, because a half-recorded one looks complete to the user.
    static func trimmed(_ records: [RemovalRecord], keeping protected: Set<UUID>) -> [RemovalRecord] {
        Batches.trimmed(records, maximum: maximumRecords, batch: \.batch, date: \.date, keeping: protected)
    }
}
