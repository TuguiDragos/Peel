import Foundation
import PeelCore

enum Removals {
    /// Records what moved as one batch in History, which the app reads too, and every failure in the log of
    /// refusals. An item missing from `sizes` is recorded as unknown. Returns false when History couldn't be written.
    static func record(
        _ result: TrashResult,
        from source: String,
        key sourceKey: String? = nil,
        sizes: [URL: Int64],
        tool: String,
        in log: RemovalLog = RemovalLog(),
        refusals: RefusalLog = RefusalLog()
    ) async -> Bool {
        await refusals.add(result.failures, source: source, sourceKey: sourceKey, tool: tool)
        guard !result.trashed.isEmpty else { return true }
        let records = RemovalPart(source: source, sourceKey: sourceKey, tool: tool).records(of: result, sizes: sizes, batch: UUID())
        return await log.add(records).records != nil
    }
}
