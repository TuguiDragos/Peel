import Foundation
@testable import Peel
import PeelCore
import Testing

@MainActor
struct RemovalHistoryStoreTests {
    @Test func aReadThatFindsNothingNewChangesNothing() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "PeelTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let refusals = RefusalLog(url: folder.appending(path: "refusals.json"))
        await refusals.add(
            [TrashFailure(url: URL(filePath: "/Users/me/kept"), reason: .lastCopy)], source: "Example", tool: "duplicates"
        )
        let history = RemovalHistoryStore(
            log: RemovalLog(url: folder.appending(path: "removals.json")),
            refusals: refusals,
            knowsTheExclusions: { true }
        )
        await history.load()
        let revision = history.revision

        await history.load()

        #expect(history.revision == revision)
        #expect(history.refusalBatches.count == 1)
    }
}
