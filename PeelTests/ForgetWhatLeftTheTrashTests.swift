import Foundation
@testable import Peel
@testable import PeelCore
import Testing

@MainActor
struct ForgetWhatLeftTheTrashTests {
    private func history(in folder: URL, knowingTheExclusions: Bool = true) -> RemovalHistoryStore {
        RemovalHistoryStore(
            log: RemovalLog(url: folder.appending(path: "removals.json")),
            refusals: RefusalLog(url: folder.appending(path: "refusals.json")),
            knowsTheExclusions: { knowingTheExclusions }
        )
    }

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

    @Test func asksAboutWhatLeftInEveryRemovalAndForgetsOnlyWhatIsStillGone() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "PeelTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let trash = folder.appending(path: "Trash", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        let history = history(in: folder)
        await record([["One", "Two"], ["Three", "Four"]], into: history, trash: trash)
        try Data().write(to: trash.appending(path: "One"))
        await history.load()

        let found = await history.whatLeftTheTrash()
        #expect(ForgetWhatLeftTheTrash.question(for: found) == "Forget 3 items in 2 removals?")

        try Data().write(to: trash.appending(path: "Three"))
        await history.forgetWhatLeftTheTrash(found)
        #expect(Set(history.records.map(\.originalURL.lastPathComponent)) == ["One", "Three"])
        #expect(ForgetWhatLeftTheTrash.question(for: await history.whatLeftTheTrash()) == nil)

        try FileManager.default.removeItem(at: trash.appending(path: "Three"))
        let last = await history.whatLeftTheTrash()
        #expect(ForgetWhatLeftTheTrash.question(for: last) == "Forget 1 item in 1 removal?")
    }

    @Test func forgetsNothingWhileRemovalsAreHeld() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "PeelTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let trash = folder.appending(path: "Trash", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        await record([["Gone"]], into: history(in: folder), trash: trash)
        let held = history(in: folder, knowingTheExclusions: false)
        await held.load()

        let found = await held.whatLeftTheTrash()
        await held.forgetWhatLeftTheTrash(found)
        await held.forget(held.records)

        #expect(found.records.count == 1)
        #expect(held.records.count == 1)
    }
}
