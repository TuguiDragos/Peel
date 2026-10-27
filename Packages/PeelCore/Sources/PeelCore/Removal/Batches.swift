import Foundation

/// The rule History and the refusal log share for staying quick to read: past a cap, the oldest removals are
/// dropped whole, because an entry cut in part would read as all there was.
enum Batches {
    /// Sorts `records` newest first and drops the oldest batches while what they `weigh` together is beyond
    /// `maximum`, each whole, never one in `protected`. A batch is dated by its oldest record, the date History shows
    /// for it.
    static func trimmed<Record, Batch: Hashable>(
        _ records: [Record],
        maximum: Int,
        weighing weight: (Record) -> Int = { _ in 1 },
        batch: (Record) -> Batch,
        date: (Record) -> Date,
        keeping protected: Set<Batch> = []
    ) -> [Record] {
        let sorted = records.sorted { date($0) > date($1) }
        var total = sorted.reduce(0) { $0 + weight($1) }
        guard total > maximum else { return sorted }

        let batches = Dictionary(grouping: sorted, by: batch)
        let dates = batches.mapValues { $0.map(date).min() ?? .distantPast }
        var dropped: Set<Batch> = []
        for key in batches.keys.sorted(by: { dates[$0] ?? .distantPast < dates[$1] ?? .distantPast })
        where total > maximum {
            guard !protected.contains(key) else { continue }
            dropped.insert(key)
            total -= batches[key]?.reduce(0) { $0 + weight($1) } ?? 0
        }
        return sorted.filter { !dropped.contains(batch($0)) }
    }

    /// `records` as `encode` writes them, in at most `limit` bytes: the oldest batches are dropped whole until they
    /// fit, so the file is never bigger than its reader reads back. Batches in `protected` stay even when they alone
    /// are bigger. Once over, it keeps to nine tenths of `limit`, so the removals that follow don't each pay for a fit.
    static func fitting<Record, Batch: Hashable>(
        _ records: [Record],
        within limit: Int,
        batch: (Record) -> Batch,
        date: (Record) -> Date,
        keeping protected: Set<Batch>,
        encode: ([Record]) throws -> Data
    ) rethrows -> (records: [Record], data: Data) {
        var kept = records
        var data = try encode(kept)
        while data.count > limit {
            // Each record weighs what it takes written alone, so one pass drops about as much as is too much.
            let weighed = try kept.map { (record: $0, weight: try encode([$0]).count) }
            let total = weighed.reduce(0) { $0 + $1.weight }
            let fewer = trimmed(
                weighed, maximum: total - (data.count - limit / 10 * 9), weighing: \.weight,
                batch: { batch($0.record) }, date: { date($0.record) }, keeping: protected
            ).map(\.record)
            guard fewer.count < kept.count else { break }
            kept = fewer
            data = try encode(kept)
        }
        return (kept, data)
    }
}
