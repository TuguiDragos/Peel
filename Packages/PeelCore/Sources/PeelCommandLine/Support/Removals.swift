import Foundation
import PeelCore

enum Removals {
    /// Records what moved as one batch in History, which the app reads too, and every failure in the log of
    /// refusals. Returns false when History couldn't be written.
    static func record(
        _ result: TrashResult,
        from source: String,
        key sourceKey: String? = nil,
        sizes: [URL: Int64],
        tool: String,
        in log: RemovalLog = RemovalLog(),
        refusals: RefusalLog = RefusalLog()
    ) async -> Bool {
        await refusals.add(result.failures, source: source, tool: tool)
        guard !result.trashed.isEmpty else { return true }
        let batch = UUID()
        let records = result.trashed.map {
            RemovalRecord(batch: batch, item: $0, size: sizes[$0.originalURL] ?? 0, source: source, sourceKey: sourceKey, tool: tool)
        }
        return await log.add(records).records != nil
    }
}
