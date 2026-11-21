import ArgumentParser
import CryptoKit
import Foundation
@testable import PeelCommandLine
@testable import PeelCore
import Synchronization
import Testing

struct HistorySealTests {
    private let seal = HistorySeal(key: SymmetricKey(size: .bits256))

    private func record(going original: String, in directory: borrowing TemporaryDirectory) throws -> RemovalRecord {
        let trashed = try directory.file("home/.Trash/\(URL(filePath: original).lastPathComponent)", bytes: 4)
        return RemovalRecord(
            batch: UUID(),
            item: TrashedItem(originalURL: directory.url.appending(path: original), trashedURL: trashed, date: .now),
            size: 4, source: "Editor", tool: "applications"
        )
    }

    @Test func aRecordPeelSealedIsTrustedAndOneChangedSinceIsNot() throws {
        let directory = try TemporaryDirectory()
        let home = directory.url.appending(path: "home", directoryHint: .isDirectory)
        let sealed = try record(going: "home/Projects/notes.txt", in: directory).sealed(by: seal)
        let written = try JSONEncoder().encode(sealed)
        let readBack = try JSONDecoder().decode(RemovalRecord.self, from: written)

        #expect(seal.trust(of: readBack) == .sealed)
        #expect(readBack.refusalBySeal(seal, guardedPlacesConfirmed: false, home: home) == nil)

        var text = try #require(String(data: written, encoding: .utf8))
        text = text.replacingOccurrences(of: "Projects", with: "Library\\/Containers\\/org.example.other\\/Data")
        let changed = try JSONDecoder().decode(RemovalRecord.self, from: Data(text.utf8))
        #expect(seal.trust(of: changed) == .forged)
        #expect(changed.refusalBySeal(seal, guardedPlacesConfirmed: true, home: home) == .changedOutsidePeel)
    }

    @Test func aSealAnEarlierKeyMadeIsNoSealAndNeverAForgedOne() throws {
        let directory = try TemporaryDirectory()
        let home = directory.url.appending(path: "home", directoryHint: .isDirectory)
        let earlier = HistorySeal(key: SymmetricKey(size: .bits256))
        let kept = try record(going: "home/Projects/notes.txt", in: directory).sealed(by: earlier)
        let guarded = try record(going: "home/Documents/notes.txt", in: directory).sealed(by: earlier)

        #expect(seal.trust(of: kept) == .unsealed)
        #expect(kept.refusalBySeal(seal, guardedPlacesConfirmed: false, home: home) == nil)
        #expect(guarded.refusalBySeal(seal, guardedPlacesConfirmed: false, home: home) == .guardedPlace(.documents))
        #expect(guarded.refusalBySeal(seal, guardedPlacesConfirmed: true, home: home) == nil)
    }

    @Test func aRecordWithoutASealGoesIntoAGuardedPlaceOnlyOnTheWordOfThePerson() throws {
        let directory = try TemporaryDirectory()
        let home = directory.url.appending(path: "home", directoryHint: .isDirectory)
        let container = try record(going: "home/Library/Containers/org.example.other/Data/notes.txt", in: directory)

        #expect(container.refusalBySeal(seal, guardedPlacesConfirmed: false, home: home)
            == .guardedPlace(.container("org.example.other")))
        #expect(container.refusalBySeal(seal, guardedPlacesConfirmed: true, home: home) == nil)
        #expect(try record(going: "home/Projects/a.txt", in: directory)
            .refusalBySeal(seal, guardedPlacesConfirmed: false, home: home) == nil)
        for (place, expected) in [("Desktop", GuardedPlace.desktop), ("Documents", .documents), ("Downloads", .downloads)] {
            let url = home.appending(path: "\(place)/a.txt")
            #expect(GuardedPlace(of: url, home: home) == expected)
        }
        #expect(GuardedPlace(of: home.appending(path: "Library/Mobile Documents/x"), home: home) == .iCloudDrive)
        #expect(GuardedPlace(of: home.appending(path: "Library/Group Containers/group.org.example/x"), home: home)
            == .groupContainer("group.org.example"))
    }

    @Test func onlyAJournalLinePeelSealedComesBackAsARecordPeelVouchesFor() async throws {
        let directory = try TemporaryDirectory()
        let history = directory.url.appending(path: "Peel/removals.json")
        let journal = RemovalJournal(beside: history)
        let moved = TrashedItem(
            originalURL: directory.url.appending(path: "home/Projects/a.txt"),
            trashedURL: try directory.file("home/.Trash/a.txt", bytes: 1), date: .now
        )
        let ended = try endedProcess()
        try await HistorySeal.$standIn.withValue(seal) {
            journal.note([moved], batch: UUID(), by: ended)
            let records = try #require(await RemovalLog(url: history).load().records)
            #expect(records.map { seal.trust(of: $0) } == [.sealed])
        }
    }

    @Test func aJournalLineChangedSinceItWasSealedGivesARecordThatStaysForged() async throws {
        let directory = try TemporaryDirectory()
        let history = directory.url.appending(path: "Peel/removals.json")
        let journal = RemovalJournal(beside: history)
        let moved = TrashedItem(
            originalURL: directory.url.appending(path: "home/Projects/a.txt"),
            trashedURL: try directory.file("home/.Trash/a.txt", bytes: 1), date: .now
        )
        let ended = try endedProcess()
        try await HistorySeal.$standIn.withValue(seal) {
            journal.note([moved], batch: UUID(), by: ended)
            let lines = try String(contentsOf: journal.url, encoding: .utf8)
            try lines.replacingOccurrences(of: "Projects", with: "Documents")
                .write(to: journal.url, atomically: true, encoding: .utf8)

            let records = try #require(await RemovalLog(url: history).load().records)
            #expect(records.map { seal.trust(of: $0) } == [.forged])
        }
    }

    /// A process that has ended, which no running process can be taken for.
    private func endedProcess() throws -> RemovalJournal.Writer {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/true")
        try process.run()
        process.waitUntilExit()
        return RemovalJournal.Writer(pid: process.processIdentifier, started: 1)
    }

    /// A read of the key that answers `seal` only once `open` is called, as a Keychain waiting for the person does.
    private func pendingReading(
        answering seal: HistorySeal
    ) -> (reading: HistorySeal.Reading, open: @Sendable () -> Void) {
        let gate = DispatchSemaphore(value: 0)
        let reading = HistorySeal.Reading()
        reading.allow {
            gate.wait()
            return seal
        }
        return (reading, { gate.signal() })
    }

    @Test func aRecordAddedBeforeTheKeyAnswersWaitsAndIsSealed() async throws {
        let directory = try TemporaryDirectory()
        let log = RemovalLog(url: directory.url.appending(path: "Peel/removals.json"))
        let added = try record(going: "home/Projects/notes.txt", in: directory)
        let (reading, open) = pendingReading(answering: seal)

        let records = await HistorySeal.$reading.withValue(reading) {
            async let outcome = log.add([added])
            try? await Task.sleep(for: .milliseconds(200))
            open()
            return await outcome.records
        }

        #expect(try #require(records).map { seal.trust(of: $0) } == [.sealed])
    }

    @Test func aJournalLineTakenInBeforeTheKeyAnswersWaitsAndIsSealed() async throws {
        let directory = try TemporaryDirectory()
        let history = directory.url.appending(path: "Peel/removals.json")
        let moved = TrashedItem(
            originalURL: directory.url.appending(path: "home/Projects/a.txt"),
            trashedURL: try directory.file("home/.Trash/a.txt", bytes: 1), date: .now
        )
        let ended = try endedProcess()
        HistorySeal.$standIn.withValue(seal) { RemovalJournal(beside: history).note([moved], batch: UUID(), by: ended) }
        let (reading, open) = pendingReading(answering: seal)

        let records = await HistorySeal.$reading.withValue(reading) {
            async let outcome = RemovalLog(url: history).load()
            try? await Task.sleep(for: .milliseconds(200))
            open()
            return await outcome.records
        }

        #expect(try #require(records).map { seal.trust(of: $0) } == [.sealed])
    }

    @Test func aLineWrittenAtAMoveBeforeTheKeyAnswersWaitsAndIsSealed() async throws {
        let directory = try TemporaryDirectory()
        let journal = RemovalJournal(beside: directory.url.appending(path: "Peel/removals.json"))
        let file = try directory.file("home/Library/Caches/org.example.cache/data")
        let trash = try directory.directory("home/.Trash")
        let service = TrashService(
            environment: SearchEnvironment(
                homeDirectory: directory.url.appending(path: "home"), rootDirectory: directory.url.appending(path: "root")
            ),
            journal: journal
        ) { url in
            let target = trash.appending(path: url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: target)
            return target
        }
        let (reading, open) = pendingReading(answering: seal)

        let moved = await HistorySeal.$reading.withValue(reading) {
            async let result = service.trash([file])
            try? await Task.sleep(for: .milliseconds(200))
            open()
            return await result
        }

        #expect(moved.trashed.count == 1)
        let lines = journal.entries().filter { $0.isBeforeTheMove != true }
        #expect(!lines.isEmpty)
        #expect(lines.map { seal.trust(of: $0) }.allSatisfy { $0 == .sealed })
    }

    @Test func theKeyIsReadOnceAndOnlyWhereItIsAllowed() async {
        let reads = Reads()
        let gate = DispatchSemaphore(value: 0)
        let reading = HistorySeal.Reading()
        await reading.answered()
        for _ in 0..<2 {
            reading.allow {
                reads.add()
                gate.wait()
                return HistorySeal(key: SymmetricKey(size: .bits256))
            }
            reading.start()
        }
        #expect(reading.seal == nil)

        gate.signal()
        await reading.answered()

        #expect(reading.seal != nil)
        #expect(reads.value == 1)
    }

    @Test func peelPutsNothingBackIntoAGuardedPlaceWithoutAskingFirst() async throws {
        let directory = try TemporaryDirectory()
        let home = directory.url.appending(path: "home", directoryHint: .isDirectory)
        let handwritten = try record(going: "home/Library/Containers/org.example.other/Data/notes.txt", in: directory)
        let log = RemovalLog(url: directory.url.appending(path: "Peel/removals.json"))
        _ = await log.add([handwritten])
        let service = TrashService(
            environment: SearchEnvironment(
                homeDirectory: home, rootDirectory: directory.url.appending(path: "root", directoryHint: .isDirectory)
            ),
            moveToTrash: { _ in throw CocoaError(.fileWriteUnknown) }
        )

        let collected = Output.Collected()
        let command = try #require(
            try PeelCommand.parseAsRoot(["restore", String(handwritten.batch.uuidString.prefix(8)), "-y"])
                as? RestoreCommand
        )
        await Output.$collected.withValue(collected) {
            try? await command.run(in: log, using: service)
        }

        #expect(handwritten.trashedURL.isThere)
        #expect(!handwritten.originalURL.isThere)
        #expect((collected.output + collected.notes).contains("which macOS guards"), "\(collected.notes)")
    }
}

private final class Reads: Sendable {
    private let count = Mutex(0)

    func add() { count.withLock { $0 += 1 } }

    var value: Int { count.withLock { $0 } }
}
