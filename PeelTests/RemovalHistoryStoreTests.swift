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
        withObservationTracking({ _ = history.rereads }, onChange: {
            MainActor.assumeIsolated { seen.withLock { $0 = history.batches.first?.records.count } }
        })
        await history.readAgainIfInUse()

        #expect(seen.withLock { $0 } == 1, "the page looked in the Trash before History was read again")
        _ = await RemovalLog(url: url).remove([records[1].id])
        await history.readAgainIfInUse()
        #expect(history.batches.isEmpty)
        #expect(history.undoTitle == nil, "Undo still offered what peel put back")
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
