import Foundation
@testable import Peel
import PeelCore
import Testing

@MainActor
struct RemovalBarTests {
    private func parts(_ count: Int) -> [CarriedSelection.Part] {
        (1...count).map { index in
            CarriedSelection.Part(
                page: CarriedSelection.Page(tool: "orphans", scope: "org.example.gone\(index)"),
                title: "org.example.gone\(index)", source: "org.example.gone\(index)", sourceKey: nil,
                sizes: [URL(filePath: "/Users/me/Library/Caches/org.example.gone\(index)"): 4_096]
            )
        }
    }

    @Test func listsTheFirstPagesOfALongSelectionAndCountsTheItemsOfTheRest() {
        let lines = RemovalBar.lines(for: parts(80))
        let most = RemovalFailureAlert.mostListed
        #expect(lines.count == most + 1)
        for (index, line) in lines.prefix(most).enumerated() {
            #expect(line.hasPrefix("org.example.gone\(index + 1):"), "\(line)")
        }
        #expect(lines.last?.contains("76") == true, "\(lines.last ?? "")")
        #expect(RemovalBar.lines(for: parts(most)).count == most)
    }

    /// A selection History couldn't keep in one removal is refused before Peel asks to move it.
    @Test func refusesASelectionHistoryCouldNotKeep() {
        let many = (0...RemovalLog.maximumRecords).map { URL(filePath: "/Users/me/Library/Caches/org.example.app\($0)") }
        let selection = CarriedSelection.Part(
            page: Tool.duplicates.page(), title: "Duplicates", source: "Duplicates", sourceKey: "tool",
            sizes: Dictionary(uniqueKeysWithValues: many.map { ($0, 1) })
        )

        let tooMany = RemovalBar.tooMany(in: [selection])

        #expect(tooMany?.count == many.count)
        #expect(tooMany?.most == RemovalLog.maximumRecords)
        #expect(RemovalBar.tooMany(in: parts(3)) == nil)
    }

    @Test func anActionHistoryDoesntRecordWaitsOnlyForTheExclusions() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "PeelTests-\(UUID().uuidString)")
        let unreadable = folder.appending(path: "removals.json")
        try FileManager.default.createDirectory(at: unreadable, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let history = RemovalHistoryStore(
            log: RemovalLog(url: unreadable), refusals: RefusalLog(url: folder.appending(path: "refusals.json")),
            knowsTheExclusions: { true }
        )
        history.checkReadability()
        #expect(history.isUnreadable)

        #expect(RemovalBar.mayAct(recordsInHistory: false, history: history, exclusionsAreKnown: true))
        #expect(!RemovalBar.mayAct(recordsInHistory: false, history: history, exclusionsAreKnown: false))
        #expect(!RemovalBar.mayAct(recordsInHistory: true, history: history, exclusionsAreKnown: true))
    }
}
