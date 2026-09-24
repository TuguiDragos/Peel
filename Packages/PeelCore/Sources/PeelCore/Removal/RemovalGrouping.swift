public import Foundation

/// One removal as History shows it: the records that moved together, largest first, and one Peel could not
/// measure before them. `grouped` lists the removals newest first, and lives here rather than in the app so the
/// rule can be tested.
public struct RemovalGroup: Sendable, Hashable, Identifiable {
    public let id: UUID
    public let source: String
    public let sourceKey: String?
    public let tool: String
    /// When the batch was moved: the earliest of its records' dates, since each item is stamped as it moves.
    public let date: Date
    public let records: [RemovalRecord]

    public var size: SizeTotal { records.totalSize }
}

extension RemovalRecord {
    public static func grouped(_ records: [RemovalRecord]) -> [RemovalGroup] {
        Dictionary(grouping: records, by: \.batch)
            .map { batch, records in
                let sorted = records.sorted {
                    let (lhs, rhs) = (SizeTotal([$0.size]), SizeTotal([$1.size]))
                    return lhs != rhs ? lhs > rhs : $0.originalURL.path(percentEncoded: false) < $1.originalURL.path(percentEncoded: false)
                }
                return RemovalGroup(
                    id: batch,
                    source: sorted.first?.source ?? "",
                    sourceKey: sorted.first?.sourceKey,
                    tool: sorted.first?.tool ?? "",
                    date: sorted.map(\.date).min() ?? .now,
                    records: sorted
                )
            }
            .sorted { $0.date != $1.date ? $0.date > $1.date : $0.id.uuidString < $1.id.uuidString }
    }
}
