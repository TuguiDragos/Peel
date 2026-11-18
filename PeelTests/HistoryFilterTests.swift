import Foundation
@testable import Peel
@testable import PeelCore
import Testing

@MainActor
struct HistoryFilterTests {
    private func history(in folder: URL) -> RemovalHistoryStore {
        RemovalHistoryStore(
            log: RemovalLog(url: folder.appending(path: "removals.json")),
            refusals: RefusalLog(url: folder.appending(path: "refusals.json")),
            knowsTheExclusions: { true }
        )
    }

    /// Records each removal as moved into `trash`, where a test then puts the files that are still there.
    private func record(_ removals: [[String]], into history: RemovalHistoryStore, trash: URL) async {
        let part = RemovalPart(source: "Example", sourceKey: nil, tool: Tool.developer.rawValue)
        for names in removals {
            var removal = RemovalInProgress()
            let items = names.map {
                TrashedItem(
                    originalURL: trash.deletingLastPathComponent().appending(path: $0),
                    trashedURL: trash.appending(path: $0), date: .now
                )
            }
            await history.record(TrashResult(trashed: items), part: part, sizes: [:], in: &removal)
            history.finish(removal)
        }
    }

    @Test func looksAgainOnceTheTrashIsLookedAtAgainThoughHistoryListsTheSame() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "PeelTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let trash = folder.appending(path: "Trash", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        let history = history(in: folder)
        await record([["One"]], into: history, trash: trash)
        try Data().write(to: trash.appending(path: "One"))
        await history.load()
        let before = HistoryList.look(isOn: true, in: history)

        try FileManager.default.removeItem(at: trash.appending(path: "One"))
        await history.reload()

        #expect(history.batches.count == 1)
        #expect(HistoryList.look(isOn: true, in: history) != before, "the filter kept what it found before the Trash was emptied")
    }
}
