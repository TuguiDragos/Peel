import Foundation

/// The rule History and the refusal log share for staying quick to read: past a cap, the oldest removals are
/// dropped whole, because an entry cut in part would read as all there was.
enum Batches {
    /// Sorts `records` newest first and drops the oldest batches beyond `maximum`, each whole, never one in
    /// `protected`. A batch is dated by its oldest record, the date History shows for it.
    static func trimmed<Record, Batch: Hashable>(
        _ records: [Record],
        maximum: Int,
        batch: (Record) -> Batch,
        date: (Record) -> Date,
        keeping protected: Set<Batch> = []
    ) -> [Record] {
        let sorted = records.sorted { date($0) > date($1) }
        guard sorted.count > maximum else { return sorted }

        let batches = Dictionary(grouping: sorted, by: batch)
        let dates = batches.mapValues { $0.map(date).min() ?? .distantPast }
        var total = sorted.count
        var dropped: Set<Batch> = []
        for key in batches.keys.sorted(by: { dates[$0] ?? .distantPast < dates[$1] ?? .distantPast }) where total > maximum {
            guard !protected.contains(key) else { continue }
            dropped.insert(key)
            total -= batches[key]?.count ?? 0
        }
        return sorted.filter { !dropped.contains(batch($0)) }
    }
}
