public import Foundation

/// One removal as History shows it: the records that moved together, largest first, and one Peel could not
/// measure before them. `grouped` lists the removals newest first, and lives here rather than in the app so the
/// rule can be tested.
public struct RemovalGroup: Sendable, Hashable, Identifiable {
    public let id: UUID
    public let parts: [RemovalPart]
    /// When the batch was moved: the earliest of its records' dates, since each item is stamped as it moves.
    public let date: Date
    public let records: [RemovalRecord]

    public var size: SizeTotal { records.totalSize }
}

extension RemovalRecord {
    public static func grouped(_ records: [RemovalRecord]) -> [RemovalGroup] {
        Dictionary(grouping: records, by: \.batch)
            .map { batch, records in
                // Each record's size and path are worked out once rather than at every comparison: History holds
                // up to `RemovalLog.maximumRecords` records, and one removal can hold thousands.
                let sorted = records
                    .map { (size: SizeTotal([$0.size]), path: $0.originalURL.path(percentEncoded: false), record: $0) }
                    .sorted { $0.size != $1.size ? $0.size > $1.size : $0.path < $1.path }
                    .map(\.record)
                return RemovalGroup(
                    id: batch,
                    parts: RemovalPart.of(sorted.map { ($0.date, $0.part) }),
                    date: sorted.map(\.date).min() ?? .now,
                    records: sorted
                )
            }
            .sorted { $0.date != $1.date ? $0.date > $1.date : $0.id.uuidString < $1.id.uuidString }
    }
}

/// What Peel was asked to move in one removal and did not, as History shows it.
public struct RefusalGroup: Sendable, Hashable, Identifiable {
    public let id: UUID
    public let parts: [RemovalPart]
    public let date: Date
    public let records: [RefusalRecord]
}

extension RefusalRecord {
    /// The refusals one removal to an entry, newest first, each entry's records by path.
    public static func grouped(_ records: [RefusalRecord]) -> [RefusalGroup] {
        Dictionary(grouping: records, by: { $0.batch ?? $0.id })
            .map { batch, records in
                let sorted = records.map { (path: $0.url.path(percentEncoded: false), record: $0) }
                    .sorted { $0.path < $1.path }
                    .map(\.record)
                return RefusalGroup(
                    id: batch,
                    parts: RemovalPart.of(sorted.map { ($0.date, $0.part) }),
                    date: sorted.map(\.date).min() ?? .now,
                    records: sorted
                )
            }
            .sorted { $0.date != $1.date ? $0.date > $1.date : $0.id.uuidString < $1.id.uuidString }
    }
}

/// Where some of a removal's records came from: the tool, and the source it names, such as an app or a group of
/// orphaned files. A removal from one page has one part, and one that moved what was selected in several tools
/// has one for each, in the order they moved.
public struct RemovalPart: Sendable, Hashable {
    public let source: String
    /// The key of a source Peel names itself, so History can show it in the user's language.
    public let sourceKey: String?
    public let tool: String

    public init(source: String, sourceKey: String?, tool: String) {
        self.source = source
        self.sourceKey = sourceKey
        self.tool = tool
    }

    /// The parts of one removal, each once, in the order its first record moved. Two parts that moved at the same
    /// moment keep one order, by tool and then by source.
    public static func of(_ records: some Sequence<(date: Date, part: RemovalPart)>) -> [RemovalPart] {
        var first: [RemovalPart: Date] = [:]
        for (date, part) in records {
            first[part] = min(first[part] ?? date, date)
        }
        return first
            .sorted {
                $0.value != $1.value ? $0.value < $1.value : ($0.key.tool, $0.key.source) < ($1.key.tool, $1.key.source)
            }
            .map(\.key)
    }
}

extension RemovalPart {
    /// History's records of what moved from this part, all in `batch`, each with its size in `sizes`, and none
    /// where it was not measured.
    public func records(of result: TrashResult, sizes: [URL: Int64], batch: UUID) -> [RemovalRecord] {
        result.trashed.map {
            RemovalRecord(
                batch: batch,
                item: $0,
                size: sizes[$0.originalURL] ?? (result.emptied.contains($0.originalURL) ? 0 : nil),
                source: source,
                sourceKey: sourceKey,
                tool: tool
            )
        }
    }
}

extension RemovalRecord {
    public var part: RemovalPart { RemovalPart(source: source, sourceKey: sourceKey, tool: tool) }
}

extension RefusalRecord {
    public var part: RemovalPart { RemovalPart(source: source, sourceKey: sourceKey, tool: tool) }
}
