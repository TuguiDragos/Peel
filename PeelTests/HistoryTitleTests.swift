import Foundation
@testable import Peel
import PeelCore
import Testing

@MainActor
struct HistoryTitleTests {
    @Test func namesTheFirstPagesOfALongRemovalAndFindsItByAnyOfThem() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "PeelTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let history = RemovalHistoryStore(
            log: RemovalLog(url: folder.appending(path: "removals.json")),
            refusals: RefusalLog(url: folder.appending(path: "refusals.json")),
            knowsTheExclusions: { true }
        )
        var removal = RemovalInProgress()
        for index in 1...30 {
            let name = String(format: "project%02d", index)
            let json = #"{"originalURL": "file:///Users/me/\#(name)/node_modules", "trashedURL": "file:///Users/me/.Trash/node_modules \#(index)", "date": \#(index)}"#
            let moved = try JSONDecoder().decode(TrashedItem.self, from: Data(json.utf8))
            let refused = TrashFailure(url: URL(filePath: "/Users/me/\(name)/build"), reason: .lastCopy)
            await history.record(
                TrashResult(trashed: [moved], failures: [refused]),
                part: RemovalPart(source: name, sourceKey: nil, tool: Tool.projects.rawValue),
                sizes: [:],
                in: &removal
            )
        }
        history.finish(removal)

        let named = "project01, project02, project03, project04, and 26 more pages"
        let batch = try #require(history.batches.first)
        #expect(batch.title == named)
        #expect(history.undoTitle == "Undo Remove \(named)")
        let found = await SearchText.matching("project30", among: history.batches, keys: history.searchKeys)
        #expect(found?.map(\.id) == [batch.id])
        let refused = try #require(history.refusalBatches.first)
        #expect(refused.title == named)
        let foundRefused = await SearchText.matching(
            "project30", among: history.refusalBatches, keys: history.refusalSearchKeys
        )
        #expect(foundRefused?.map(\.id) == [refused.id])
    }
}
