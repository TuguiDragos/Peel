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
    public let date: Date
    public let source: String
    /// A key for a source Peel names itself, as in `RemovalRecord.sourceKey`.
    public let sourceKey: String?
    public let tool: String

    public init(failure: TrashFailure, date: Date = .now, source: String, sourceKey: String? = nil, tool: String, batch: UUID? = nil) {
        id = UUID()
        self.batch = batch
        url = failure.url
        reason = failure.reason.name
        detail = failure.reason.detail
        self.date = date
        self.source = source
        self.sourceKey = sourceKey
        self.tool = tool
    }
}

/// A record of what Peel was asked to move and refused, so the decisions can be read back. Only refusals of
/// items the user asked to move go in, never what a scan held back. Access goes through an actor and an
/// advisory lock on the file, as in `RemovalLog`, because the `peel` tool writes here too.
public actor RefusalLog {
    static let maximumRecords = 5_000

    public let url: URL

    public init(url: URL = RemovalHistory.refusalsURL) {
        self.url = url
    }

    public func load() -> [RefusalRecord] {
        FileLock.whileHeld(beside: url) { current() ?? [] }
    }

    /// Writes down what one removal refused. The parts of one pass through several tools share its `batch`, so
    /// History shows them as one entry.
    public func add(_ failures: [TrashFailure], source: String, sourceKey: String? = nil, tool: String, batch: UUID = UUID()) {
        let date = Date.now
        let records = failures.map { RefusalRecord(failure: $0, date: date, source: source, sourceKey: sourceKey, tool: tool, batch: batch) }
        guard !records.isEmpty else { return }
        FileLock.whileHeld(beside: url) {
            guard let existing = current() else { return }
            write(Array((existing + records).sorted { $0.date > $1.date }.prefix(Self.maximumRecords)))
        }
    }

    public func clear() -> Bool {
        FileLock.whileHeld(beside: url) {
            guard !url.isMissing else { return true }
            return (try? FileManager.default.removeItem(at: url)) != nil
        }
    }

    /// The records in the file. A file that fails to decode is set aside and its readable rows kept. Nil when the
    /// file could not be read or set aside, so it must not be written over.
    private func current() -> [RefusalRecord]? {
        guard !url.isMissing else { return [] }
        guard let data = BoundedRead.data(at: url, maximum: 16 * 1_024 * 1_024) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = LogTime.decoding
        if let records = try? decoder.decode([RefusalRecord].self, from: data) {
            return records
        }
        // A row that a later version wrote, or that a hand edit broke, must not cost the other rows.
        let readable = (try? decoder.decode([Row].self, from: data))?.compactMap(\.record) ?? []
        guard DamagedFile.setAside(url) != nil else { return nil }
        if !readable.isEmpty {
            write(readable)
        }
        return readable
    }

    /// One row of the file. A row with a missing or malformed field is dropped and the others are kept: any
    /// process can rewrite the file.
    private struct Row: Decodable {
        let record: RefusalRecord?

        init(from decoder: any Decoder) {
            record = try? RefusalRecord(from: decoder)
        }
    }

    private func write(_ records: [RefusalRecord]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = LogTime.encoding
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(records) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
