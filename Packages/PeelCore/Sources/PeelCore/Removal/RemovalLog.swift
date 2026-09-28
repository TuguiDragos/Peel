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
}

/// The record of everything Peel moved to the Trash, so History can put it back.
///
/// An actor because every change is a read-modify-write of one file: two removals at once
/// would otherwise overwrite each other. None of its methods suspend once they start, so
/// actor reentrancy cannot interleave two of them.
public actor RemovalLog {
    /// The most records the file keeps. Past this, the oldest batches are dropped whole, never in part.
    static let maximumRecords = 20_000
    /// The largest file read as History. The file is Peel's, but any process of the user can rewrite it, and
    /// 20,000 records take about 6 MB.
    static let maximumBytes = 64 * 1_024 * 1_024

    public nonisolated let url: URL
    public private(set) var problem: RemovalLogProblem?
    /// What removals moved and have not recorded yet, item by item.
    private let journal: RemovalJournal
    private let totals: URL

    public init(url: URL = RemovalHistory.defaultURL) {
        self.url = url
        journal = RemovalJournal(beside: url)
        totals = RemovalTotals.url(beside: url)
    }

    /// Reads the log. The read takes the lock too, because reading a damaged file sets it aside and writes back
    /// the rows that could be read.
    public func load() -> RemovalLogOutcome {
        whileNoOtherProcessWrites { RemovalLogOutcome(records: current(), problem: problem) }
    }

    /// The places in the Trash where an item Peel moved still is, whichever process moved it: what History records
    /// and what a removal under way has written down so far. Spelled as `PathPattern.comparablePath` spells them.
    public func placesInTheTrash() -> Set<String> {
        let items = (load().records ?? []).map(\.trashedItem) + journal.entries().map(\.item)
        return Set(items.filter(\.isInTheTrash).map { PathPattern.comparablePath(of: $0.trashedURL) })
    }

    public func add(_ records: [RemovalRecord]) -> RemovalLogOutcome {
        whileNoOtherProcessWrites {
            guard !records.isEmpty else { return RemovalLogOutcome(records: current(), problem: problem) }
            guard let existing = current() else { return RemovalLogOutcome(records: nil, problem: problem) }
            let updated = Self.trimmed(existing + records, keeping: Set(records.map(\.batch)))
            guard write(updated, orNote: .couldNotRecord) else { return RemovalLogOutcome(records: nil, problem: problem) }
            RemovalTotals.change(at: totals) { $0.add(records) }
            journal.forget(records.map(\.trashedItem))
            // A removal that is recorded clears an earlier `.couldNotRecord`.
            if problem == .couldNotRecord { problem = nil }
            return RemovalLogOutcome(records: updated, problem: problem)
        }
    }

    /// Adds totals the app kept before `peel` counted too. False when they could not be written.
    public func takeIn(_ earlier: RemovalTotals) -> Bool {
        whileNoOtherProcessWrites { RemovalTotals.change(at: totals) { $0.takeIn(earlier) } }
    }

    /// Whether History at `url` can be read, known without reading it: it is not there yet, or it opens as the file
    /// it should be. A History that cannot be read is never written over, and nothing moves meanwhile.
    public static func canBeRead(at url: URL = RemovalHistory.defaultURL) -> Bool {
        url.isMissing || BoundedRead.opens(url, maximum: maximumBytes)
    }

    /// Keeps a History that cannot be read beside the new one, under another name, and starts recording again.
    public func startOver() -> RemovalLogOutcome {
        whileNoOtherProcessWrites {
            guard stored() == nil else { return RemovalLogOutcome(records: current(), problem: problem) }
            guard DamagedFile.setAside(url) != nil else { return RemovalLogOutcome(records: nil, problem: problem) }
            problem = nil
            return RemovalLogOutcome(records: current(), problem: problem)
        }
    }

    public func remove(_ ids: Set<UUID>) -> RemovalLogOutcome {
        whileNoOtherProcessWrites {
            guard let existing = current() else { return RemovalLogOutcome(records: nil, problem: problem) }
            let updated = existing.filter { !ids.contains($0.id) }
            return RemovalLogOutcome(records: write(updated, orNote: .couldNotUpdate) ? updated : nil, problem: problem)
        }
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
        let interrupted = left.filter { !recorded.contains(RemovalJournal.Key($0.item)) }.map(\.interruptedRecord)
        var updated = records
        if !interrupted.isEmpty {
            updated = Self.trimmed(records + interrupted, keeping: Set(interrupted.map(\.batch)))
            guard write(updated, orNote: .couldNotRecord) else { return records }
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
        guard let data = BoundedRead.data(at: url, maximum: Self.maximumBytes) else {
            note(.unreadable)
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = LogTime.decoding
        if let records = try? decoder.decode([RemovalRecord].self, from: data) {
            note(nil)
            return records
        }
        // A row this version cannot read (written by a later version, or broken by hand) must not cost the rest.
        let readable = (try? decoder.decode([Row].self, from: data))?.compactMap(\.record) ?? []
        guard let setAside = DamagedFile.setAside(url) else {
            note(.unreadable)
            return nil
        }
        note(.damaged(setAside: setAside))
        guard !readable.isEmpty, write(readable, orNote: .damaged(setAside: setAside)) else { return [] }
        return readable
    }

    /// A row of the file. `record` is nil when the row does not decode.
    private struct Row: Decodable {
        let record: RemovalRecord?

        init(from decoder: any Decoder) {
            record = try? RemovalRecord(from: decoder)
        }
    }

    private func write(_ records: [RemovalRecord], orNote failure: RemovalLogProblem) -> Bool {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = LogTime.encoding
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try encoder.encode(records)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            // `.atomic` writes a temporary file and renames it, so a crash leaves either the old log or the new one.
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            // An unrecorded removal is the most serious problem, so a later failure never replaces it.
            if problem != .couldNotRecord { note(failure) }
            return false
        }
    }

    /// Sorts `records` newest first and drops the oldest batches beyond `maximumRecords`, so the file stays quick
    /// to read. A batch is dropped whole, and never one in `protected`: a removal is recorded completely or not
    /// at all, because a half-recorded one looks complete to the user.
    static func trimmed(_ records: [RemovalRecord], keeping protected: Set<UUID>) -> [RemovalRecord] {
        Batches.trimmed(records, maximum: maximumRecords, batch: \.batch, date: \.date, keeping: protected)
    }
}
