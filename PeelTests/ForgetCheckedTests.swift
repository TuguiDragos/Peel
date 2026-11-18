import Foundation
@testable import Peel
@testable import PeelCore
import Testing

@MainActor
struct ForgetCheckedTests {
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

    private func found(checkedIn history: RemovalHistoryStore) async -> ForgetCheckedBar.Found {
        let removals = history.batches.filter { history.checkedRemovals.contains($0.id) }
        return ForgetCheckedBar.Found(
            leftTheTrash: await RemovalStanding.leftTheTrash(removals.flatMap(\.records)),
            entries: history.checkedRefusals
        )
    }

    @Test func asksAboutWhatLeftInTheCheckedRemovalsAndForgetsOnlyWhatIsStillGone() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "PeelTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let trash = folder.appending(path: "Trash", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        let history = history(in: folder)
        await record([["One", "Two"], ["Three", "Four"], ["Five"]], into: history, trash: trash)
        try Data().write(to: trash.appending(path: "One"))
        await history.load()
        history.checkedRemovals = Set(
            history.batches.filter { !$0.records.contains { $0.originalURL.lastPathComponent == "Five" } }.map(\.id)
        )

        let found = await found(checkedIn: history)
        #expect(ForgetCheckedBar.question(for: found) == "Forget 3 items in 2 removals?")

        try Data().write(to: trash.appending(path: "Three"))
        await history.forgetChecked(found.leftTheTrash, entries: found.entries)
        #expect(Set(history.records.map(\.originalURL.lastPathComponent)) == ["One", "Three", "Five"])
        #expect(history.checkedRemovals.isEmpty)
    }

    @Test func forgetsACheckedNotMovedEntryWhole() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "PeelTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let history = history(in: folder)
        var removal = RemovalInProgress()
        let refused = TrashFailure(url: folder.appending(path: "Stayed"), reason: .locked)
        let part = RemovalPart(source: "Example", sourceKey: nil, tool: Tool.developer.rawValue)
        await history.record(TrashResult(failures: [refused]), part: part, sizes: [:], in: &removal)
        await history.load()
        let entry = try #require(history.refusalBatches.first)
        history.checkedRefusals = [entry.id]

        let found = await found(checkedIn: history)
        #expect(ForgetCheckedBar.question(for: found) == "Forget 1 entry under Not Moved?")
        await history.forgetChecked(found.leftTheTrash, entries: found.entries)

        #expect(history.refusalBatches.isEmpty)
        #expect(history.checkedRefusals.isEmpty)
    }

    @Test func asksAboutBothKindsInOneQuestion() {
        let gone = RemovalRecord(
            batch: UUID(),
            item: TrashedItem(originalURL: URL(filePath: "/a/One"), trashedURL: URL(filePath: "/t/One"), date: .now),
            size: 1, source: "Example", tool: "developer"
        )
        let found = ForgetCheckedBar.Found(leftTheTrash: LeftTheTrash([gone]), entries: [UUID()])

        #expect(ForgetCheckedBar.question(for: found) == "Forget 1 item in 1 removal and 1 entry under Not Moved?")
        #expect(ForgetCheckedBar.message(for: found).contains("Put Back"))
        let nothing = ForgetCheckedBar.Found(leftTheTrash: LeftTheTrash([]), entries: [])
        #expect(ForgetCheckedBar.question(for: nothing) == nil)
    }

    @Test func forgetsNothingWhileRemovalsAreHeld() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "PeelTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let trash = folder.appending(path: "Trash", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        await record([["Gone"]], into: history(in: folder), trash: trash)
        let held = history(in: folder, knowingTheExclusions: false)
        await held.load()
        held.checkedRemovals = Set(held.batches.map(\.id))

        let found = await found(checkedIn: held)
        await held.forgetChecked(found.leftTheTrash, entries: found.entries)

        #expect(found.leftTheTrash.records.count == 1)
        #expect(held.records.count == 1)
    }
}
