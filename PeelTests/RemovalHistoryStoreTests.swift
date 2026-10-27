import Foundation
import Observation
@testable import Peel
import PeelCore
import Synchronization
import Testing

@MainActor
struct RemovalHistoryStoreTests {
    private func moved(_ name: String) throws -> TrashResult {
        let json = #"{"originalURL": "file:///Users/me/\#(name)", "trashedURL": "file:///Users/me/.Trash/\#(name)", "date": 0}"#
        return TrashResult(trashed: [try JSONDecoder().decode(TrashedItem.self, from: Data(json.utf8))])
    }

    @Test func readsWhatPeelChangedBeforeTheRemovalsPageLooksInTheTrashAgain() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "PeelTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "removals.json")
        let history = RemovalHistoryStore(
            log: RemovalLog(url: url),
            refusals: RefusalLog(url: folder.appending(path: "refusals.json")),
            knowsTheExclusions: { true }
        )
        let part = RemovalPart(source: "Example", sourceKey: nil, tool: Tool.developer.rawValue)
        var removal = RemovalInProgress()
        await history.record(try moved("One"), part: part, sizes: [:], in: &removal)
        await history.record(try moved("Two"), part: part, sizes: [:], in: &removal)
        history.finish(removal)
        await history.load()
        let records = try #require(history.batches.first?.records)
        _ = await RemovalLog(url: url).remove([records[0].id])

        let seen = Mutex<Int?>(nil)
        withObservationTracking({ _ = history.trashLooks }, onChange: {
            MainActor.assumeIsolated { seen.withLock { $0 = history.batches.first?.records.count } }
        })
        await history.readAgainIfInUse()

        #expect(seen.withLock { $0 } == 1, "the page looked in the Trash before History was read again")
        _ = await RemovalLog(url: url).remove([records[1].id])
        await history.readAgainIfInUse()
        #expect(history.batches.isEmpty)
        #expect(history.undoTitle == nil, "Undo still offered what peel put back")
    }

    /// History's page says once how many older removals History no longer lists, and again when it leaves out more.
    @Test func saysOnceWhatHistoryNoLongerLists() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "PeelTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let prefs = try MadeUpDefaults()
        defer { prefs.forget() }
        func store() -> RemovalHistoryStore {
            RemovalHistoryStore(
                log: RemovalLog(url: folder.appending(path: "removals.json")),
                refusals: RefusalLog(url: folder.appending(path: "refusals.json")),
                knowsTheExclusions: { true },
                defaults: prefs.defaults
            )
        }
        func leaveOut(_ count: Int) throws {
            let totals = #"{"apps":0,"biggest":{"isComplete":true,"known":0},"bytes":{"isComplete":true,"known":0},"items":0,"removalsLeftOut":\#(count),"tookInEarlier":false}"#
            try Data(totals.utf8).write(to: folder.appending(path: "totals.json"))
        }

        let history = store()
        await history.load()
        #expect(history.untoldNoLongerListed == nil, "said before anything was left out")
        try leaveOut(3)
        await history.load()
        #expect(history.untoldNoLongerListed == 3)
        history.tellNoLongerListed(3)
        #expect(history.untoldNoLongerListed == nil)

        let later = store()
        await later.load()
        #expect(later.untoldNoLongerListed == nil, "said again after it was said")
        try leaveOut(5)
        await later.load()
        #expect(later.untoldNoLongerListed == 5)
    }

    /// Nothing moves or comes back while Peel removes itself, since Remove Peel takes History and Peel's folder.
    @Test func movesNothingWhilePeelRemovesItself() {
        let folder = FileManager.default.temporaryDirectory.appending(path: "PeelTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        final class Removal { var runs = false }
        let removal = Removal()
        let history = RemovalHistoryStore(
            log: RemovalLog(url: folder.appending(path: "removals.json")),
            refusals: RefusalLog(url: folder.appending(path: "refusals.json")),
            knowsTheExclusions: { true },
            removesPeel: { removal.runs }
        )

        #expect(history.mayMove)
        removal.runs = true
        #expect(history.holdingReason == .peelRemovesItself)
        #expect(!history.mayMove)
    }

    @Test func aHistoryThatCannotBeReadIsNotCalledEmpty() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "PeelTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "removals.json")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let history = RemovalHistoryStore(
            log: RemovalLog(url: url),
            refusals: RefusalLog(url: folder.appending(path: "refusals.json")),
            knowsTheExclusions: { true }
        )

        await history.load()

        #expect(history.hasLoaded && history.batches.isEmpty)
        #expect(history.shownProblem == .unreadable)
        #expect(!history.isKnownEmpty)
    }

    @Test func tellsVoiceOverWhatForgetForgot() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "PeelTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let heard = Heard()
        let history = RemovalHistoryStore(
            log: RemovalLog(url: folder.appending(path: "removals.json")),
            refusals: RefusalLog(url: folder.appending(path: "refusals.json")),
            knowsTheExclusions: { true },
            announcing: { heard.words.append(String($0.characters)) }
        )
        let part = RemovalPart(source: "Example", sourceKey: nil, tool: Tool.developer.rawValue)
        var removal = RemovalInProgress()
        await history.record(try moved("One"), part: part, sizes: [:], in: &removal)
        await history.record(try moved("Two"), part: part, sizes: [:], in: &removal)
        history.finish(removal)
        await history.load()

        await history.forget(history.records)

        #expect(heard.words.last == "Forgot 2 items.")
        #expect(history.batches.isEmpty)
    }

    @Test func answersWhatEachStartOverDid() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "PeelTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let removals = folder.appending(path: "removals.json")
        let refusals = folder.appending(path: "refusals.json")
        try FileManager.default.createDirectory(at: removals, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: refusals, withIntermediateDirectories: true)
        let history = RemovalHistoryStore(
            log: RemovalLog(url: removals),
            refusals: RefusalLog(url: refusals),
            knowsTheExclusions: { true }
        )
        await history.load()

        #expect(await history.startOver() == .started)
        #expect(await history.startOverRefusals() == .started)
        #expect(await history.startOver() == .notNeeded)
        #expect(await history.startOverRefusals() == .notNeeded)
    }

    @Test func looksInTheTrashAgainAfterAPutBackHistoryCouldNotWrite() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "PeelTests-\(UUID().uuidString)")
        let path = folder.path(percentEncoded: false)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: path)
            try? FileManager.default.removeItem(at: folder)
        }
        let history = RemovalHistoryStore(
            log: RemovalLog(url: folder.appending(path: "removals.json")),
            refusals: RefusalLog(url: folder.appending(path: "refusals.json")),
            knowsTheExclusions: { true },
            restoring: { items, _ in
                // Back in place, and History's folder closed before History is told.
                try? FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: path)
                return items.map { _ in nil }
            }
        )
        var removal = RemovalInProgress()
        let part = RemovalPart(source: "Example", sourceKey: nil, tool: Tool.developer.rawValue)
        await history.record(try moved("Cache"), part: part, sizes: [:], in: &removal)
        history.finish(removal)
        let looks = history.trashLooks

        await history.restore(history.records, canUseHelper: false)

        #expect(history.problem == .couldNotUpdate)
        #expect(history.trashLooks == looks + 1, "the page kept saying it is in the Trash")
    }

    @Test func tellsAPutBackThatEndsAsTheOneBefore() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "PeelTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let history = RemovalHistoryStore(
            log: RemovalLog(url: folder.appending(path: "removals.json")),
            refusals: RefusalLog(url: folder.appending(path: "refusals.json")),
            knowsTheExclusions: { true },
            restoring: { items, _ in items.map { _ in .needsHelper } }
        )
        var removal = RemovalInProgress()
        let part = RemovalPart(source: "Example", sourceKey: nil, tool: Tool.developer.rawValue)
        await history.record(try moved("Driver"), part: part, sizes: [:], in: &removal)
        history.finish(removal)

        await history.restore(history.records, canUseHelper: false)
        let first = history.failures
        await history.restore(history.records, canUseHelper: false)

        #expect(history.failures == first)
        #expect(history.toldPutBacks == 2, "the second Put Back's alert never showed")
    }

    @Test func saysWhenStartingOverCouldNotSetTheOldFileAside() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "PeelTests-\(UUID().uuidString)")
        let path = folder.path(percentEncoded: false)
        try FileManager.default.createDirectory(at: folder.appending(path: "removals.json"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: folder.appending(path: "refusals.json"), withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: path)
            try? FileManager.default.removeItem(at: folder)
        }
        let history = RemovalHistoryStore(
            log: RemovalLog(url: folder.appending(path: "removals.json")),
            refusals: RefusalLog(url: folder.appending(path: "refusals.json")),
            knowsTheExclusions: { true }
        )
        await history.load()

        let startedOver = await history.startOver()
        let startedRefusalsOver = await history.startOverRefusals()

        #expect(startedOver == .couldNotSetAside && history.shownProblem == .unreadable)
        #expect(startedRefusalsOver == .couldNotSetAside && history.refusalProblem == .unreadable)
    }

    @Test func startsOverANotMovedListItCannotRead() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "PeelTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let refusals = folder.appending(path: "refusals.json")
        try FileManager.default.createDirectory(at: refusals, withIntermediateDirectories: true)
        let history = RemovalHistoryStore(
            log: RemovalLog(url: folder.appending(path: "removals.json")),
            refusals: RefusalLog(url: refusals),
            knowsTheExclusions: { true }
        )
        await history.load()
        #expect(history.refusalProblem == .unreadable)

        await history.startOverRefusals()

        #expect(history.refusalProblem == nil)
        #expect(FileManager.default.fileExists(atPath: refusals.path(percentEncoded: false)) == false)
    }

    @Test func aRefusalThatCouldNotBeRecordedIsStillSaidWhenHistoryOpens() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "PeelTests-\(UUID().uuidString)")
        let path = folder.path(percentEncoded: false)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: path)
            try? FileManager.default.removeItem(at: folder)
        }
        let history = RemovalHistoryStore(
            log: RemovalLog(url: folder.appending(path: "removals.json")),
            refusals: RefusalLog(url: folder.appending(path: "refusals.json")),
            knowsTheExclusions: { true }
        )
        let refused = TrashResult(failures: [TrashFailure(url: URL(filePath: "/Users/me/kept"), reason: .lastCopy)])
        var removal = RemovalInProgress()
        await history.record(
            refused, part: RemovalPart(source: "Example", sourceKey: nil, tool: Tool.developer.rawValue), sizes: [:],
            in: &removal
        )

        await history.load()

        #expect(history.refusalProblem == .couldNotRecord)
    }

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

private final class Heard {
    var words: [String] = []
}
