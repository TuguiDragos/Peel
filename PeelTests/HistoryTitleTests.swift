import Foundation
@testable import Peel
@testable import PeelCore
import Testing

@MainActor
struct HistoryTitleTests {
    @Test func namesSeveralForgottenReceiptsByHowManyThereAre() {
        let receipt = { (identifier: String) in
            PackageReceipt(
                identifier: identifier, version: nil, installDate: nil, volume: URL(filePath: "/"), items: [],
                nothingLeftOnDisk: true
            )
        }
        let few = ["org.example.one", "org.example.two"].map(receipt)
        let many = (1...5).map { receipt("org.example.p\($0)") }

        #expect(PackageLibrary.source(of: few) == ("org.example.one, org.example.two", nil))
        #expect(PackageLibrary.source(of: many) == ("5 receipts", "receipts.5"))
        #expect(RemovalBatch.title(source: "written before", key: "receipts.5", tool: .packages)
            == String(inflecting: "^[\(5) receipt](inflect: true)"))
    }

    /// A page's title is no thing that went: emptying Xcode's caches on the Developer page doesn't remove Xcode.
    @Test func undoNamesTheMoveAndNotThePage() throws {
        let record = { (path: String, tool: Tool) in
            RemovalRecord(
                batch: UUID(),
                item: TrashedItem(
                    originalURL: URL(filePath: path), trashedURL: URL(filePath: "/Users/me/.Trash/x"), date: .now
                ),
                size: 1, source: "Xcode", tool: tool.rawValue
            )
        }
        let part = { (tool: Tool) in RemovalPart(source: "Xcode", sourceKey: nil, tool: tool.rawValue) }
        let caches = [
            record("/Users/me/Library/Developer/Xcode/DerivedData", .developer),
            record("/Users/me/Library/Caches/com.apple.dt.Xcode", .developer),
        ]

        #expect(RemovalBatch.undoTitle(of: [part(.developer)], title: "Xcode", records: caches)
            == String(inflecting: "Undo Move of ^[\(2) Item](inflect: true)"))
        #expect(RemovalBatch.undoTitle(of: [part(.developer)], title: "Xcode", records: [caches[0]])
            == String(localized: "Undo Move of “\("DerivedData")”"))
        let app = record("/Applications/Xcode.app", .applications)
        #expect(RemovalBatch.undoTitle(of: [part(.applications)], title: "Xcode", records: [app, caches[0]])
            == String(localized: "Undo Remove \("Xcode")"))
        let filesOnly = [record("/Users/me/Library/Caches/com.apple.dt.Xcode", .applications)]
        #expect(RemovalBatch.undoTitle(of: [part(.applications)], title: "Xcode", records: filesOnly)
            == String(localized: "Undo Move of “\("com.apple.dt.Xcode")”"))
    }

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
        #expect(history.undoTitle == String(inflecting: "Undo Move of ^[\(30) Item](inflect: true)"))
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
