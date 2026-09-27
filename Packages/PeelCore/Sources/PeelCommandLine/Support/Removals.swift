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
        // History first: it is the way back for what moved, and the refusal log may have to wait for another writer.
        var isRecorded = true
        if !result.trashed.isEmpty {
            let part = RemovalPart(source: source, sourceKey: sourceKey, tool: tool)
            isRecorded = await log.add(part.records(of: result, sizes: sizes, batch: UUID())).records != nil
        }
        await refusals.add(result.failures, source: source, sourceKey: sourceKey, tool: tool)
        return isRecorded
    }
}
