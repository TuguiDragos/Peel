import Foundation
@testable import Peel
@testable import PeelCore
import Testing

@MainActor
struct HistoryLeftTheTrashTests {
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
        #expect(HistoryList.look(in: history) != before, "the rows kept what Peel found before the Trash was emptied")
    }

    @Test func aRowSaysHowMuchOfItsRemovalLeftTheTrash() {
        #expect(HistoryList.leftKind(gone: 3, of: 3) == .all)
        #expect(HistoryList.leftKind(gone: 1, of: 3) == .part)
        #expect(HistoryList.leftKind(gone: 0, of: 3) == nil)
    }

    @Test func selectWhatLeftTheTrashChecksExactlyTheRemovalsSomethingHasLeftAndNothingUnderNotMoved() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "PeelTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let trash = folder.appending(path: "Trash", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        let history = history(in: folder)
        await record([["One", "Two"], ["Three", "Four"], ["Five"]], into: history, trash: trash)
        for name in ["One", "Five"] { try Data().write(to: trash.appending(path: name)) }
        var notMoved = RemovalInProgress()
        let stayed = TrashFailure(url: folder.appending(path: "Stayed"), reason: .locked)
        let part = RemovalPart(source: "Example", sourceKey: nil, tool: Tool.developer.rawValue)
        await history.record(TrashResult(failures: [stayed]), part: part, sizes: [:], in: &notMoved)
        await history.load()
        let stillInTheTrash = try #require(
            history.batches.first { $0.records.map(\.originalURL.lastPathComponent) == ["Five"] }
        )
        history.checkedRemovals = [stillInTheTrash.id]
        history.checkedRefusals = Set(history.refusalBatches.map(\.id))
        try #require(history.checkedRefusals.count == 1)

        let gone = HistoryList.gone(in: await RemovalStanding.leftTheTrash(history.records))
        HistoryList.selectWhatLeftTheTrash(among: history.batches, gone: gone, in: history)

        let checked = history.batches.filter { history.checkedRemovals.contains($0.id) }.map { batch in
            Set(batch.records.map(\.originalURL.lastPathComponent))
        }
        #expect(Set(checked) == [["One", "Two"], ["Three", "Four"]])
        #expect(history.checkedRemovals.count == 2)
        #expect(history.checkedRefusals.isEmpty, "it checked, or left checked, an entry under Not Moved")
    }

    @Test func selectWhatLeftTheTrashIsOffUntilALookFindsSuchARemovalInTheList() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "PeelTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let trash = folder.appending(path: "Trash", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        let history = history(in: folder)
        await record([["One"], ["Two"]], into: history, trash: trash)
        try Data().write(to: trash.appending(path: "One"))
        await history.load()
        let gone = HistoryList.gone(in: await RemovalStanding.leftTheTrash(history.records))
        let inTheTrash = history.batches.filter { $0.records.map(\.originalURL.lastPathComponent) == ["One"] }

        #expect(HistoryList.whatLeftTheTrash(among: history.batches, gone: nil).isEmpty)
        #expect(HistoryList.whatLeftTheTrash(among: history.batches, gone: gone).count == 1)
        #expect(HistoryList.whatLeftTheTrash(among: inTheTrash, gone: gone).isEmpty)
        #expect(HistoryList.whatLeftTheTrash(among: [], gone: gone).isEmpty)
    }
}
