import Foundation
@testable import Peel
@testable import PeelCore
import Testing

struct RemovalOutcomeTests {
    @Test func tellsOfShellFilesThatStillNameWhatMoved() {
        let outcome = RemovalOutcome()
        let reference = ShellReferences.Reference(file: URL(filePath: "/Users/me/.zshrc"), line: 12)

        outcome.report(TrashResult(), shellReferences: [reference])
        #expect(!outcome.isEmpty && outcome.shellReferences == [reference])
        outcome.report(TrashResult())
        #expect(outcome.shellReferences == [reference], "a removal with nothing to tell changes nothing")

        outcome.clear()
        #expect(outcome.isEmpty)
    }

    @Test func tellsOfARemovalHistoryCouldNotRecord() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "PeelTests-\(UUID().uuidString)")
        let peel = folder.appending(path: "Peel", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: peel, withIntermediateDirectories: true)
        try Data("[]".utf8).write(to: peel.appending(path: "removals.json"))
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o555], ofItemAtPath: peel.path(percentEncoded: false)
        )
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: peel.path(percentEncoded: false)
            )
            try? FileManager.default.removeItem(at: folder)
        }
        let outcome = RemovalOutcome()
        let history = RemovalHistoryStore(
            log: RemovalLog(url: peel.appending(path: "removals.json")),
            refusals: RefusalLog(url: folder.appending(path: "refusals.json")),
            outcome: outcome
        )
        let item = #"{"originalURL": "file:///Users/me/Cache", "trashedURL": "file:///Users/me/.Trash/Cache", "date": 0}"#
        let moved = try JSONDecoder().decode(TrashedItem.self, from: Data(item.utf8))

        await history.record(TrashResult(trashed: [moved]), tool: .developer, source: "Xcode", sizes: [:])

        #expect(outcome.historyCouldNotRecord && !outcome.isEmpty)
        #expect(RemovalFailureAlert.message(for: outcome).hasPrefix("What moved is in the Trash"))
        #expect(RemovalFailureAlert.details(for: outcome).hasPrefix("What moved is in the Trash"))
    }

    private func history(
        in folder: URL, outcome: RemovalOutcome, staying: String? = nil, because failure: RestoreFailure = .needsHelper
    ) -> RemovalHistoryStore {
        RemovalHistoryStore(
            log: RemovalLog(url: folder.appending(path: "removals.json")),
            refusals: RefusalLog(url: folder.appending(path: "refusals.json")),
            outcome: outcome,
            knowsTheExclusions: { true },
            restoring: { items, _ in
                TrashService.Restored(
                    failures: items.map { $0.originalURL.lastPathComponent == staying ? failure : nil },
                    movedAside: items.map { _ in nil }
                )
            }
        )
    }

    private func moved(_ names: [String]) throws -> TrashResult {
        try TrashResult(trashed: names.map { name in
            let item = #"{"originalURL": "file:///Users/me/\#(name)", "trashedURL": "file:///Users/me/.Trash/\#(name)", "date": 0}"#
            return try JSONDecoder().decode(TrashedItem.self, from: Data(item.utf8))
        })
    }

    private final class Asked {
        var count = 0
        var knowsTheExclusions = true
        var release: CheckedContinuation<Void, Never>?
    }

    private func history(in folder: URL, asked: Asked, waits: Bool = false) -> RemovalHistoryStore {
        RemovalHistoryStore(
            log: RemovalLog(url: folder.appending(path: "removals.json")),
            refusals: RefusalLog(url: folder.appending(path: "refusals.json")),
            knowsTheExclusions: { asked.knowsTheExclusions },
            restoring: { items, _ in
                asked.count += 1
                if waits, asked.count == 1 { await withCheckedContinuation { asked.release = $0 } }
                return TrashService.Restored(failures: items.map { _ in nil }, movedAside: items.map { _ in nil })
            }
        )
    }

    @Test func aPutBackAndAnUndoMoveNothingWhileMovesAreHeld() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "PeelTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let asked = Asked()
        let history = history(in: folder, asked: asked)
        await history.record(try moved(["Cache"]), tool: .plugins, source: "Plug-ins", sizes: [:])

        asked.knowsTheExclusions = false
        await history.restore(history.records, canUseHelper: false)
        await history.undoLastRemoval()

        #expect(asked.count == 0)
        #expect(history.undoTitle != nil, "the removal stays undoable for when moves are let go")
    }

    @Test func onePutBackRunsAtATime() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "PeelTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let asked = Asked()
        let history = history(in: folder, asked: asked, waits: true)
        await history.record(try moved(["Cache"]), tool: .plugins, source: "Plug-ins", sizes: [:])
        let records = history.records

        let first = Task { await history.restore(records, canUseHelper: false) }
        while asked.release == nil { try await Task.sleep(for: .milliseconds(1)) }
        await history.restore(records, canUseHelper: false)
        asked.release?.resume()
        _ = await first.value

        #expect(asked.count == 1)
    }

    @Test func anUndoThatLeavesAnItemSaysWhyWhereverThePersonIs() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "PeelTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let outcome = RemovalOutcome()
        let history = history(in: folder, outcome: outcome, staying: "Driver")
        await history.record(try moved(["Cache", "Driver"]), tool: .plugins, source: "Plug-ins", sizes: [:])

        await history.undoLastRemoval()

        #expect(outcome.putBackFailures.map(\.url.lastPathComponent) == ["Driver"])
        #expect(outcome.putBackAsked == 2)
        #expect(outcome.putBackFailures.first?.failure == .needsHelper)
        #expect(history.undoTitle != nil, "what stayed can be put back once the helper can")
    }

    @Test func anUndoTheHelpersOwnRuleRefusedIsNotOfferedAgain() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "PeelTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let outcome = RemovalOutcome()
        let history = history(in: folder, outcome: outcome, staying: "Synth", because: .notAllowedByTheHelper("x"))
        await history.record(try moved(["Synth"]), tool: .plugins, source: "Plug-ins", sizes: [:])

        await history.undoLastRemoval()

        #expect(outcome.putBackFailures.map(\.url.lastPathComponent) == ["Synth"])
        #expect(history.undoTitle == nil)
    }

    @Test func undoGoesOnceItsRemovalIsPutBackFromHistory() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "PeelTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let history = history(in: folder, outcome: RemovalOutcome())
        await history.record(try moved(["Cache"]), tool: .plugins, source: "Plug-ins", sizes: [:])
        #expect(history.undoTitle != nil)

        await history.restore(history.records, canUseHelper: false)

        #expect(history.undoTitle == nil)
    }

    @Test func whatPeelRestorePutBackIsListedAgainToo() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "PeelTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let history = history(in: folder, outcome: RemovalOutcome())
        await history.record(try moved(["Cache", "Other"]), tool: .plugins, source: "Plug-ins", sizes: [:])
        #expect(!history.needsRescanAfterPutBack(.plugins))
        let peel = RemovalLog(url: folder.appending(path: "removals.json"))

        _ = await peel.remove([try #require(history.records.first).id])
        await history.readAgainIfInUse()

        #expect(history.needsRescanAfterPutBack(.plugins))
        history.rescannedAfterPutBack(.plugins, at: history.putBacks)
        await history.readAgainIfInUse()
        #expect(!history.needsRescanAfterPutBack(.plugins), "nothing left since")
    }

    @Test func aPutBackTellsEveryPageWhicheverMovedWhatCameBack() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "PeelTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let history = history(in: folder, outcome: RemovalOutcome())
        await history.record(try moved(["Cache"]), tool: .plugins, source: "Plug-ins", sizes: [:])
        #expect(!history.needsRescanAfterPutBack(.plugins) && !history.needsRescanAfterPutBack(.space))

        await history.undoLastRemoval()

        #expect(history.needsRescanAfterPutBack(.plugins))
        #expect(history.needsRescanAfterPutBack(.plugins), "it still owes its scan")
        history.rescannedAfterPutBack(.plugins, at: history.putBacks)
        #expect(!history.needsRescanAfterPutBack(.plugins), "once it has listed again")
        #expect(history.needsRescanAfterPutBack(.space))
    }
}
