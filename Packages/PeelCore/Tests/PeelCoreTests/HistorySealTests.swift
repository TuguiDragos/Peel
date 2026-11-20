import ArgumentParser
import CryptoKit
import Foundation
@testable import PeelCommandLine
@testable import PeelCore
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
        #expect(HistorySeal(key: SymmetricKey(size: .bits256), isNew: true).trust(of: readBack) == .unsealed)
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

    /// A process that has ended, which no running process can be taken for.
    private func endedProcess() throws -> RemovalJournal.Writer {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/true")
        try process.run()
        process.waitUntilExit()
        return RemovalJournal.Writer(pid: process.processIdentifier, started: 1)
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
