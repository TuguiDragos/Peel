import ArgumentParser
import Foundation
@testable import PeelCommandLine
@testable import PeelCore
import Testing

/// `peel history` reads the file the app writes, and `peel restore` undoes from it.
struct HistoryCommandTests {
    private func command<Command: AsyncParsableCommand>(_ arguments: [String]) throws -> Command {
        try #require(try PeelCommand.parseAsRoot(arguments) as? Command)
    }

    private func logs(in directory: borrowing TemporaryDirectory) -> (removals: RemovalLog, refusals: RefusalLog) {
        (RemovalLog(url: directory.url.appending(path: "Peel/removals.json")),
         RefusalLog(url: directory.url.appending(path: "Peel/refusals.json")))
    }

    /// A restore only ever puts things back, so nothing here is allowed to move anything to the Trash.
    private func service(in directory: borrowing TemporaryDirectory) -> TrashService {
        TrashService(
            environment: SearchEnvironment(
                homeDirectory: directory.url.appending(path: "home", directoryHint: .isDirectory),
                rootDirectory: directory.url.appending(path: "root", directoryHint: .isDirectory)
            ),
            moveToTrash: { _ in throw CocoaError(.fileWriteUnknown) }
        )
    }

    /// One removal of one file, already in a Trash of its own, ready to be put back.
    private func removal(in directory: borrowing TemporaryDirectory) throws -> (record: RemovalRecord, original: URL) {
        let original = directory.url.appending(path: "home/Documents/report.pdf")
        let trashed = try directory.file("home/.Trash/report.pdf", bytes: 40)
        return (RemovalRecord(
            batch: UUID(),
            item: TrashedItem(originalURL: original, trashedURL: trashed, date: .now),
            size: 40,
            source: "Editor",
            tool: "applications"
        ), original)
    }

    @Test func writesEveryColumnOfARemoval() throws {
        let directory = try TemporaryDirectory()
        let removal = try removal(in: directory)
        let rows = HistoryCommand.rows(for: Batch.all(in: [removal.record]))

        #expect(rows[0] == ["ID", "WHEN", "WHAT", "ITEMS", "SIZE", "STATE"])
        #expect(rows.count == 2)
        #expect(rows[1][0] == String(removal.record.batch.uuidString.prefix(8)).lowercased())
        #expect(rows[1][1] == Inventory.day(removal.record.date, timeZone: .current))
        #expect(rows[1][2] == "Editor")
        #expect(rows[1][3] == "1")
        #expect(rows[1][4] == "40 bytes")
        #expect(rows[1][5] == "in the Trash")
    }

    /// The state column is the whole point of the list: what can still be put back from here. One removal
    /// is one batch, so a batch half emptied from the Trash has to say so.
    @Test func saysWhichRemovalsCanStillBePutBack() throws {
        let directory = try TemporaryDirectory()
        let batch = UUID()
        func record(_ name: String, trashed: URL) -> RemovalRecord {
            RemovalRecord(
                batch: batch,
                item: TrashedItem(originalURL: URL(filePath: "/Users/me/\(name)"), trashedURL: trashed, date: .now),
                size: 10,
                source: "Editor",
                tool: "applications"
            )
        }
        let here = record("here.pdf", trashed: try directory.file("home/.Trash/here.pdf", bytes: 10))
        let gone = record("gone.pdf", trashed: directory.url.appending(path: "home/.Trash/emptied.pdf"))

        #expect(HistoryCommand.rows(for: Batch.all(in: [here]))[1][5] == "in the Trash")
        #expect(HistoryCommand.rows(for: Batch.all(in: [gone]))[1][5] == "gone from the Trash")
        #expect(HistoryCommand.rows(for: Batch.all(in: [here, gone]))[1][5] == "partly gone from the Trash")
        #expect(HistoryCommand.rows(for: Batch.all(in: [here, gone])).count == 2, "one removal is one row")
    }

    /// The WHY column shows macOS's own message when macOS refused, and Peel's name for the rule when Peel did.
    @Test func writesEveryColumnOfARefusal() {
        let when = Date(timeIntervalSince1970: 1_790_000_000)
        let records = [
            RefusalRecord(failure: TrashFailure(url: URL(filePath: "/Users/me/Library/Mail"), reason: .protectedLocation), date: when, source: "Editor", tool: "applications"),
            RefusalRecord(failure: TrashFailure(url: URL(filePath: "/Users/me/x.bin"), reason: .failed("no such file")), date: when, source: "Editor", tool: "applications"),
        ]
        let rows = HistoryCommand.rows(for: records)

        #expect(rows[0] == ["WHEN", "WHAT", "WHY", "PATH"])
        #expect(rows[1] == [Inventory.day(when, timeZone: .current), "Editor", "protected-location", "/Users/me/Library/Mail"])
        #expect(rows[2] == [Inventory.day(when, timeZone: .current), "Editor", "no such file", "/Users/me/x.bin"])
    }

    /// What `arguments` print, read the way a person or a script would read it.
    private func printed(_ arguments: [String], from logs: (removals: RemovalLog, refusals: RefusalLog)) async throws -> String {
        let collected = Output.Collected()
        try await Output.$collected.withValue(collected) {
            try await (command(arguments) as HistoryCommand).run(in: logs.removals, refusals: logs.refusals)
        }
        return collected.output
    }

    private func listed(_ json: String) throws -> [Any] {
        try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [Any])
    }

    /// With nothing recorded, the command prints a sentence rather than an empty table, and `--json` prints an
    /// empty list.
    @Test func saysSoWhenThereIsNothingToList() async throws {
        let directory = try TemporaryDirectory()
        let logs = logs(in: directory)

        #expect(try await printed(["history"], from: logs) == "Peel hasn't moved anything to the Trash yet.\n")
        #expect(try listed(try await printed(["history", "--json"], from: logs)).isEmpty)
        #expect(try await printed(["history", "--refused"], from: logs) == "Peel hasn't refused anything it was asked to move.\n")
        #expect(try listed(try await printed(["history", "--refused", "--json"], from: logs)).isEmpty)
    }

    /// `--limit` is what the command prints, in the table and in `--json` alike.
    @Test func showsAtMostWhatWasAskedFor() async throws {
        let directory = try TemporaryDirectory()
        let logs = logs(in: directory)
        _ = await logs.removals.add(try (0..<3).map { _ in try removal(in: directory).record })

        let table = try await printed(["history", "--limit", "2"], from: logs)
        let json = try await printed(["history", "--limit", "2", "--json"], from: logs)

        #expect(table.split(separator: "\n").count == 3, "a header and two removals, not \(table)")
        #expect(try listed(json).count == 2)
        #expect(Batch.all(in: try #require(await logs.removals.load().records)).count == 3, "listing forgot nothing")
    }

    @Test func forgetsTheRefusalsWhenAsked() async throws {
        let directory = try TemporaryDirectory()
        let logs = logs(in: directory)
        await logs.refusals.add([TrashFailure(url: URL(filePath: "/x"), reason: .lastCopy)], source: "Editor", tool: "duplicates")

        try await (command(["history", "--refused", "--clear"]) as HistoryCommand).run(in: logs.removals, refusals: logs.refusals)

        #expect(await logs.refusals.load().isEmpty)
    }

    /// A History file that cannot be read is reported as an error, never shown as an empty History.
    @Test func refusesToListAHistoryItCannotRead() async throws {
        let directory = try TemporaryDirectory()
        let logs = logs(in: directory)
        let file = try directory.file("Peel/removals.json", contents: Data("not json".utf8))
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: file.path(percentEncoded: false))
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path(percentEncoded: false)) }

        await #expect(throws: CommandFailure.self) {
            try await (command(["history"]) as HistoryCommand).run(in: logs.removals, refusals: logs.refusals)
        }
        await #expect(throws: CommandFailure.self) {
            try await (command(["restore", "abcd", "-y"]) as RestoreCommand).run(in: logs.removals, using: service(in: directory))
        }
    }

    @Test func refusesAnIdentifierThatNamesNothing() async throws {
        let directory = try TemporaryDirectory()
        let logs = logs(in: directory)
        _ = await logs.removals.add([try removal(in: directory).record])

        await #expect(throws: CommandFailure.self) {
            try await (command(["restore", "ffffffff", "-y"]) as RestoreCommand).run(in: logs.removals, using: service(in: directory))
        }
    }

    @Test func refusesWhenNothingIsLeftInTheTrash() async throws {
        let directory = try TemporaryDirectory()
        let logs = logs(in: directory)
        let removal = try removal(in: directory)
        _ = await logs.removals.add([removal.record])
        try FileManager.default.removeItem(at: removal.record.trashedURL)

        await #expect(throws: CommandFailure.self) {
            try await (command(["restore", String(removal.record.batch.uuidString.prefix(8)), "-y"]) as RestoreCommand)
                .run(in: logs.removals, using: service(in: directory))
        }
    }

    @Test func aDryRunPutsNothingBack() async throws {
        let directory = try TemporaryDirectory()
        let logs = logs(in: directory)
        let removal = try removal(in: directory)
        _ = await logs.removals.add([removal.record])

        try await (command(["restore", String(removal.record.batch.uuidString.prefix(8)), "--dry-run"]) as RestoreCommand)
            .run(in: logs.removals, using: service(in: directory))

        #expect(!FileManager.default.fileExists(atPath: removal.original.path(percentEncoded: false)))
        #expect(await logs.removals.load().records?.count == 1)
    }

    @Test func putsARemovalBackAndForgetsIt() async throws {
        let directory = try TemporaryDirectory()
        let logs = logs(in: directory)
        let removal = try removal(in: directory)
        _ = await logs.removals.add([removal.record])

        try await (command(["restore", String(removal.record.batch.uuidString.prefix(8)), "-y"]) as RestoreCommand)
            .run(in: logs.removals, using: service(in: directory))

        #expect(FileManager.default.fileExists(atPath: removal.original.path(percentEncoded: false)))
        #expect(await logs.removals.load().records?.isEmpty == true)
    }

    /// A file already sits where the item would go back, so the restore cannot finish. It exits 1 and keeps the
    /// record.
    @Test func aRestoreThatCouldNotFinishExitsOne() async throws {
        let directory = try TemporaryDirectory()
        let logs = logs(in: directory)
        let removal = try removal(in: directory)
        _ = await logs.removals.add([removal.record])
        try directory.file("home/Documents/report.pdf", bytes: 1)

        await #expect(throws: ExitCode.failure) {
            try await (command(["restore", String(removal.record.batch.uuidString.prefix(8)), "-y"]) as RestoreCommand)
                .run(in: logs.removals, using: service(in: directory))
        }
        #expect(await logs.removals.load().records?.count == 1)
    }
}
