public import Foundation
internal import PeelPrivileged

public struct RefusalRecord: Sendable, Codable, Hashable, Identifiable {
    public let id: UUID
    /// What one removal refused shares a batch, so History shows it as one entry. A record without one is an entry
    /// of its own.
    public let batch: UUID?
    public let url: URL
    /// `TrashFailure.Reason.name`: a word, not the sentence shown on screen, so later versions can still read it.
    public let reason: String
    public let detail: String?
    public let error: SystemError?
    public let date: Date
    public let source: String
    /// A key for a source Peel names itself, as in `RemovalRecord.sourceKey`.
    public let sourceKey: String?
    public let tool: String

    public init(
        failure: TrashFailure,
        date: Date = .now,
        source: String,
        sourceKey: String? = nil,
        tool: String,
        batch: UUID? = nil
    ) {
        id = UUID()
        self.batch = batch
        url = failure.url
        reason = failure.reason.name
        detail = failure.reason.detail
        error = failure.error
        self.date = date
        self.source = source
        self.sourceKey = sourceKey
        self.tool = tool
    }
}

extension RefusalRecord {
    /// Why the item stayed, with what macOS reported worded in the reader's language (`SystemError`), or nil for a
    /// word this version doesn't know.
    public var failureReason: TrashFailure.Reason? {
        if reason == "failed", let error { return .failed(error.description(of: url)) }
        return TrashFailure.Reason(name: reason, detail: detail)
    }
}

/// What went wrong reading or writing the refusal log, for History to say.
public enum RefusalLogProblem: Sendable, Equatable {
    /// The file could not be decoded. It was set aside under this name, and the rows that could be read were kept.
    case damaged(setAside: URL)
    /// The file could not be read or set aside, so nothing is written to it: it is the only copy of what was
    /// refused.
    case unreadable
    /// What the last removal refused could not be written down.
    case couldNotRecord
}

/// A record of what Peel was asked to move and refused, so the decisions can be read back. Only refusals of
/// items the user asked to move go in, never what a scan held back. Access goes through an actor and an
/// advisory lock on the file, as in `RemovalLog`, because the `peel` tool writes here too.
public actor RefusalLog {
    static let maximumRecords = 5_000
    static let maximumBytes = 16 * 1_024 * 1_024

    public nonisolated let url: URL
    /// What was last read or written, kept while the file stays the same, as in `RemovalLog`.
    private var kept: (file: FileIdentity, records: [RefusalRecord])?
    private var problem: RefusalLogProblem?
    private let readLimit: Int

    public init(url: URL = RemovalHistory.refusalsURL) {
        self.init(url: url, readLimit: Self.maximumBytes)
    }

    init(url: URL, readLimit: Int) {
        self.url = url
        self.readLimit = readLimit
    }

    /// The records, with what is still to be said about the file (`note`). Nil records when the file could not be
    /// read: what was refused is then not known, which is not the same as nothing refused.
    public func load() -> (records: [RefusalRecord]?, problem: RefusalLogProblem?) {
        FileLock.whileHeld(beside: url) {
            let records = current()
            return (records, problem)
        }
    }

    /// Writes down what one removal refused, and says what kept it from being written. The parts of one pass
    /// through several tools share its `batch`, so History shows them as one entry. Past the cap, the oldest
    /// removals are dropped whole.
    @discardableResult
    public func add(
        _ failures: [TrashFailure], source: String, sourceKey: String? = nil, tool: String, batch: UUID = UUID(),
        date: Date = .now
    ) -> RefusalLogProblem? {
        let records = failures.map {
            RefusalRecord(failure: $0, date: date, source: source, sourceKey: sourceKey, tool: tool, batch: batch)
        }
        guard !records.isEmpty else { return nil }
        return FileLock.whileHeld(beside: url) {
            guard let existing = current() else { return problem }
            let kept = Batches.trimmed(
                existing + records, maximum: Self.maximumRecords, batch: { $0.batch ?? $0.id }, date: \.date,
                keeping: [batch]
            )
            guard write(kept, keeping: [batch]) else {
                note(.couldNotRecord)
                return problem
            }
            if problem == .couldNotRecord { problem = nil }
            return problem
        }
    }

    /// Keeps a file that cannot be read beside a new one, under another name, and starts writing refusals down again.
    public func startOver() -> StartOver {
        FileLock.whileHeld(beside: url) {
            guard current() == nil else { return .notNeeded }
            guard DamagedFile.setAside(url) != nil else { return .couldNotSetAside }
            problem = nil
            return .started
        }
    }

    /// Whether nothing is left to forget: no refusal written down, no file that can't be read, and no copy set aside.
    public func holdsNothing() -> Bool {
        FileLock.whileHeld(beside: url) { current() == [] && DamagedFile.copies(of: url) == [] }
    }

    /// Moves the file and the copies set aside to the Trash, so every refusal is forgotten and can still be taken back
    /// from there. Only files move, never a folder or a link put in their place, and a refusal written meanwhile waits.
    public func clear(through service: TrashService) async -> Bool {
        await FileLock.whileHeld(beside: url, waitingFor: {
            guard var files = DamagedFile.copies(of: url) else { return false }
            if !url.isMissing {
                var info = stat()
                guard lstat(url.path(percentEncoded: false), &info) == 0, info.st_mode & S_IFMT == S_IFREG else {
                    return false
                }
                files.insert(url, at: 0)
            }
            guard !files.isEmpty else { return true }
            guard await service.trashOwnFiles(files).failures.isEmpty else { return false }
            problem = nil
            return true
        })
    }

    /// The records in the file. A file that fails to decode is set aside and its readable rows kept. Nil when the
    /// file could not be read or set aside, so it must not be written over.
    private func current() -> [RefusalRecord]? {
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
        if let records = try? decoder.decode([RefusalRecord].self, from: data) {
            note(nil)
            kept = (read.file, records)
            return records
        }
        // A row that a later version wrote, or that a hand edit broke, must not cost the other rows.
        let readable = (try? decoder.decode([Row].self, from: data))?.compactMap(\.record) ?? []
        guard let setAside = DamagedFile.setAside(url) else {
            note(.unreadable)
            return nil
        }
        note(.damaged(setAside: setAside))
        if !readable.isEmpty {
            write(readable)
        }
        return readable
    }

    /// Sets `problem`, or clears it after a good read (nil), as `RemovalLog` does: a damaged file stays reported while
    /// the copy set aside is there, since it is the only trace of it, and `.couldNotRecord` until a refusal is written.
    private func note(_ problem: RefusalLogProblem?) {
        if problem == nil {
            if case .damaged(let setAside) = self.problem, !setAside.isMissing { return }
            if self.problem == .couldNotRecord { return }
        }
        self.problem = problem
    }

    /// One row of the file. A row with a missing or malformed field is dropped and the others are kept: any
    /// process can rewrite the file.
    private struct Row: Decodable {
        let record: RefusalRecord?

        init(from decoder: any Decoder) {
            record = try? RefusalRecord(from: decoder)
        }
    }

    /// Writes `records`, less the oldest removals that wouldn't fit in what is read back, never one in `protected`.
    @discardableResult
    private func write(_ records: [RefusalRecord], keeping protected: Set<UUID> = []) -> Bool {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = LogTime.encoding
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let fitted = try? Batches.fitting(
            records, within: readLimit, batch: { $0.batch ?? $0.id }, date: \.date, keeping: protected,
            encode: { try encoder.encode($0) }
        ) else { return false }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard (try? fitted.data.write(to: url, options: .atomic)) != nil else { return false }
        // Every writer takes the lock, so the file here is the one just written.
        kept = FileIdentity.of(url).map { ($0, fitted.records) }
        return true
    }
}
