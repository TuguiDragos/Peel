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
        let before = HistoryList.look(in: history)

        try FileManager.default.removeItem(at: trash.appending(path: "One"))
        await history.reload()

        #expect(history.batches.count == 1)
        #expect(HistoryList.look(in: history) != before, "the filter kept what it found before the Trash was emptied")
    }

    @Test func saysWhatTheFilterShowsAndWhatEachRemovalLeft() {
        #expect(
            HistoryList.filterSummary(shown: 23, total: 33)
                == "Showing 23 of 33 removals: those that moved something that has left the Trash since. Not Moved is hidden."
        )
        #expect(
            HistoryList.filterSummary(shown: 4, total: 4)
                == "Every removal here moved something that has left the Trash since, so the filter hides only Not Moved."
        )
        #expect(HistoryList.leftKind(gone: 3, of: 3) == .all)
        #expect(HistoryList.leftKind(gone: 1, of: 3) == .part)
        #expect(HistoryList.leftKind(gone: 0, of: 3) == nil)
    }

    @Test func listsEveryRemovalSomethingHasLeftTheTrashOf() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "PeelTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let trash = folder.appending(path: "Trash", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        let history = history(in: folder)
        await record([["One", "Two"], ["Three", "Four"], ["Five"]], into: history, trash: trash)
        for name in ["One", "Five"] { try Data().write(to: trash.appending(path: name)) }
        await history.load()

        let left = await RemovalStanding.leftTheTrash(history.records)

        let names = history.batches.filter { left.removals.contains($0.id) }.map { batch in
            Set(batch.records.map(\.originalURL.lastPathComponent))
        }
        #expect(Set(names) == [["One", "Two"], ["Three", "Four"]])
    }

    @Test func fadesOnlyWhenALookChangesTheRowsTheFilterLists() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "PeelTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let history = history(in: folder)
        await record([["One"], ["Two"]], into: history, trash: folder.appending(path: "Trash"))
        let listed = history.batches
        let (first, second) = (listed[0].id, listed[1].id)

        #expect(!HistoryList.changesRows(listed, from: nil, to: [first]), "turning the filter on faded the column")
        #expect(HistoryList.changesRows(listed, from: [first, second], to: [first]))
        #expect(HistoryList.changesRows(listed, from: [], to: [second]))
        #expect(!HistoryList.changesRows(listed, from: [first], to: [first]))
        #expect(
            !HistoryList.changesRows(listed, from: [first, UUID()], to: [first]),
            "a removal History no longer lists faded the column again"
        )
    }
}
