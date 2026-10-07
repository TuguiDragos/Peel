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

    private let movesNothing = TrashService(environment: .current) { _ in throw CocoaError(.fileWriteUnknown) }

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

    /// The WHY column shows macOS's own message when macOS refused, and Peel's words for the rule when Peel did.
    @Test func writesEveryColumnOfARefusal() {
        let when = Date(timeIntervalSince1970: 1_790_000_000)
        let records = [
            RefusalRecord(
                failure: TrashFailure(url: URL(filePath: "/Users/me/Library/Mail"), reason: .guarded(nil)),
                date: when, source: "Editor", tool: "applications"
            ),
            RefusalRecord(failure: TrashFailure(url: URL(filePath: "/Users/me/x.bin"), reason: .failed("no such file")), date: when, source: "Editor", tool: "applications"),
        ]
        let rows = HistoryCommand.rows(for: records)

        #expect(rows[0] == ["WHEN", "WHAT", "WHY", "PATH"])
        let day = Inventory.day(when, timeZone: .current)
        #expect(rows[1] == [day, "Editor", "protected location", "/Users/me/Library/Mail"])
        #expect(rows[2] == [day, "Editor", "no such file", "/Users/me/x.bin"])
    }

    /// What `arguments` print, read the way a person or a script would read it.
    private func printed(
        _ arguments: [String],
        from logs: (removals: RemovalLog, refusals: RefusalLog)
    ) async throws -> String {
        let collected = Output.Collected()
        try await Output.$collected.withValue(collected) {
            try await (command(arguments) as HistoryCommand)
                .run(in: logs.removals, refusals: logs.refusals, trash: movesNothing)
        }
        return collected.output
    }

    private func listed(_ json: String) throws -> [Any] {
        try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [Any])
    }

    /// A removal of what was selected in several tools is named by each of their sources, in the order they
    /// moved, in the table and in `--json`, where it names no one tool and lists each part.
    @Test func namesEveryPartOfARemovalFromSeveralTools() async throws {
        let directory = try TemporaryDirectory()
        let logs = logs(in: directory)
        let batch = UUID()
        let now = Date.now
        let parts = [("Xcode", "developer", "DerivedData"), ("Peel", "projects", "node_modules"), ("Duplicates", "duplicates", "copy.bin")]
        let records = parts.enumerated().map { index, part in
            RemovalRecord(
                batch: batch,
                item: TrashedItem(
                    originalURL: directory.url.appending(path: "home/\(part.2)"),
                    trashedURL: directory.url.appending(path: "home/.Trash/\(part.2)"),
                    date: now.addingTimeInterval(Double(index))
                ),
                size: 10,
                source: part.0,
                tool: part.1
            )
        }
        _ = await logs.removals.add(records)

        #expect(HistoryCommand.rows(for: Batch.all(in: records))[1][2] == "Xcode, Peel, and Duplicates")
        #expect(HistoryCommand.rows(for: Batch.all(in: Array(records.prefix(2))))[1][2] == "Xcode and Peel")

        let removal = try #require(try listed(try await printed(["history", "--json"], from: logs)).first as? [String: Any])
        #expect(removal["tool"] is NSNull)
        let listedParts = try #require(removal["parts"] as? [[String: Any]])
        #expect(listedParts.compactMap { $0["source"] as? String } == ["Xcode", "Peel", "Duplicates"])
        #expect(listedParts.compactMap { $0["tool"] as? String } == ["developer", "projects", "duplicates"])
    }

    /// A removal cut short comes back into History with no tool, since which tool moved it is not known, and
    /// `--json` says so with null rather than a name.
    @Test func anInterruptedRemovalNamesNoTool() async throws {
        let directory = try TemporaryDirectory()
        let logs = logs(in: directory)
        let item = TrashedItem(
            originalURL: directory.url.appending(path: "home/Library/Caches/com.example.app"),
            trashedURL: directory.url.appending(path: "home/.Trash/com.example.app"),
            date: .now
        )
        let writer = RemovalJournal.Writer(pid: 0, started: 0)
        _ = await logs.removals.add([RemovalJournal.Entry(writer: writer, batch: UUID(), item: item).interruptedRecord])

        let removal = try #require(try listed(try await printed(["history", "--json"], from: logs)).first as? [String: Any])

        #expect(removal["source"] as? String == "Interrupted removal")
        #expect(removal["tool"] is NSNull)
        let parts = try #require(removal["parts"] as? [[String: Any]])
        #expect(parts.count == 1)
        #expect(parts.first?["tool"] is NSNull)
    }

    /// A removal whose items Peel cannot look at in the Trash is not called gone: nobody knows yet.
    @Test(.permissionsHold) func aRemovalPeelCannotLookAtIsNotCalledGone() throws {
        let directory = try TemporaryDirectory()
        let trashed = try directory.file("home/.Trash/report.pdf")
        let record = RemovalRecord(
            batch: UUID(),
            item: TrashedItem(originalURL: directory.url.appending(path: "home/Documents/report.pdf"), trashedURL: trashed, date: .now),
            size: 16,
            source: "Editor",
            tool: "applications"
        )
        try directory.setPermissions(0, of: "home/.Trash")
        defer { try? directory.setPermissions(0o755, of: "home/.Trash") }

        let batch = try #require(Batch.all(in: [record]).first)

        #expect(batch.state == "can't look in the Trash")
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

    /// `--limit` is what the command prints, in the table and in `--json` alike, and 20 without it.
    @Test func showsAtMostWhatWasAskedFor() async throws {
        let directory = try TemporaryDirectory()
        let logs = logs(in: directory)
        let count = HistoryCommand.defaultLimit + 1
        _ = await logs.removals.add(try (0..<count).map { _ in try removal(in: directory).record })

        let table = try await printed(["history", "--limit", "2"], from: logs)
        let json = try await printed(["history", "--limit", "2", "--json"], from: logs)
        let unlimited = try await printed(["history", "--json"], from: logs)

        #expect(table.split(separator: "\n").count == 3, "a header and two removals, not \(table)")
        #expect(try listed(json).count == 2)
        #expect(try listed(unlimited).count == 20)
        #expect(Batch.all(in: try #require(await logs.removals.load().records)).count == count, "listing forgot nothing")
    }

    /// What Peel could not measure is never printed as zero: the table says "over" while part of a removal is
    /// known, and `--json` writes `null`, for the removal and for the file alike.
    @Test func aSizeNobodyMeasuredIsNeverPrintedAsZero() async throws {
        let directory = try TemporaryDirectory()
        let logs = logs(in: directory)
        let known = try removal(in: directory).record
        let unknown = RemovalRecord(
            batch: known.batch,
            item: TrashedItem(
                originalURL: directory.url.appending(path: "home/Documents/notes.txt"),
                trashedURL: try directory.file("home/.Trash/notes.txt", bytes: 3),
                date: .now
            ),
            size: nil,
            source: "Editor",
            tool: "applications"
        )
        _ = await logs.removals.add([known, unknown])

        #expect(HistoryCommand.rows(for: Batch.all(in: [known, unknown]))[1][4] == "over 40 bytes")

        let listing = try #require(try listed(try await printed(["history", "--json"], from: logs)).first as? [String: Any])
        #expect(listing["size"] is NSNull)
        let files = try #require(listing["files"] as? [[String: Any]])
        #expect(Set(files.map { ($0["size"] as? Int).map(String.init) ?? "null" }) == ["40", "null"])
    }

    /// A caller passes the sizes it measured; an item it could not measure is left out and recorded as unknown.
    @Test func anItemLeftOutOfTheSizesIsRecordedAsUnknown() async throws {
        let directory = try TemporaryDirectory()
        let logs = logs(in: directory)
        let measured = TrashedItem(originalURL: URL(filePath: "/Users/me/a.txt"), trashedURL: URL(filePath: "/Users/me/.Trash/a.txt"), date: .now)
        let unmeasured = TrashedItem(originalURL: URL(filePath: "/Users/me/b"), trashedURL: URL(filePath: "/Users/me/.Trash/b"), date: .now)

        #expect(
            await Removals.record(
                TrashResult(trashed: [measured, unmeasured]),
                from: "Editor",
                sizes: [measured.originalURL: 5],
                tool: "applications",
                in: logs.removals,
                refusals: logs.refusals
            )
        )

        let records = try #require(await logs.removals.load().records)
        #expect(
            Dictionary(uniqueKeysWithValues: records.map { ($0.originalURL.lastPathComponent, $0.size) }) == [
                "a.txt": 5, "b": nil,
            ]
        )
    }

    /// `--limit` counts removals, as the app lists refusals one removal to an entry, and `--json` writes each removal
    /// with its items: a plain path, the reason's name and words, and every key present, `null` where nothing is known.
    @Test func listsRefusalsOneRemovalAtATime() async throws {
        let directory = try TemporaryDirectory()
        let logs = logs(in: directory)
        let old = TrashFailure(url: URL(filePath: "/Users/me/old.bin"), reason: .lastCopy)
        await logs.refusals.add([old], source: "Old", tool: "duplicates", date: .now.addingTimeInterval(-60))
        await logs.refusals.add(
            [
                TrashFailure(url: URL(filePath: "/Users/me/My Files/a.bin"), reason: .guarded(.excluded)),
                TrashFailure(url: URL(filePath: "/Users/me/b.bin"), reason: .failed("disk full")),
            ],
            source: "Editor", tool: "applications"
        )

        let text = try await printed(["history", "--refused", "--limit", "1"], from: logs)
        #expect(text.contains("a.bin") && text.contains("b.bin") && !text.contains("old.bin"))

        let removals = try listed(try await printed(["history", "--refused", "--limit", "1", "--json"], from: logs))
        let removal = try #require(removals.first as? [String: Any])
        #expect(removals.count == 1)
        #expect(removal["source"] as? String == "Editor")
        #expect(removal["tool"] as? String == "applications")
        #expect(removal["batch"] is String)
        let items = try #require(removal["items"] as? [[String: Any]])
        #expect(items.map { $0["path"] as? String } == ["/Users/me/My Files/a.bin", "/Users/me/b.bin"])
        #expect(items.map { $0["reason"] as? String } == ["excluded", "failed"])
        #expect(items.map { $0["why"] as? String } == ["excluded", "disk full"])
        #expect(items[0]["detail"] is NSNull)
    }

    @Test func refusesToClearAndWriteJSONTogether() throws {
        #expect(throws: (any Error).self) { try PeelCommand.parseAsRoot(["history", "--refused", "--clear", "--json"]) }
    }

    @Test func movesTheRefusalsToTheTrashWhenAsked() async throws {
        let directory = try TemporaryDirectory()
        let logs = logs(in: directory)
        await logs.refusals.add([TrashFailure(url: URL(filePath: "/x"), reason: .lastCopy)], source: "Editor", tool: "duplicates")
        let trash = try directory.directory("Trash")
        let service = TrashService(
            environment: SearchEnvironment(homeDirectory: directory.url, rootDirectory: directory.url)
        ) { url in
            let destination = trash.appending(path: url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: destination)
            return destination
        }

        try await (command(["history", "--refused", "--clear", "--yes"]) as HistoryCommand)
            .run(in: logs.removals, refusals: logs.refusals, trash: service)

        #expect(await logs.refusals.load().records?.isEmpty == true)
        #expect(FileManager.default.fileExists(atPath: trash.appending(path: "refusals.json").path(percentEncoded: false)))
    }

    @Test func movesNothingWhenNothingWasRefused() async throws {
        let directory = try TemporaryDirectory()
        let logs = logs(in: directory)

        let said = try await printed(["history", "--refused", "--clear", "--yes"], from: logs)

        #expect(said.contains("Peel hasn't refused anything it was asked to move."))
        #expect(!said.contains("Moved"))
    }

    @Test func asksBeforeForgettingTheRefusals() throws {
        #expect(throws: (any Error).self) { try PeelCommand.parseAsRoot(["history", "--refused", "--clear"]) }
        #expect(throws: (any Error).self) { try PeelCommand.parseAsRoot(["history", "--refused", "--yes"]) }
        _ = try PeelCommand.parseAsRoot(["history", "--refused", "--clear", "--yes"])
    }

    /// A History file that cannot be read is reported as an error, never shown as an empty History.
    @Test(.permissionsHold) func refusesToListAHistoryItCannotRead() async throws {
        let directory = try TemporaryDirectory()
        let logs = logs(in: directory)
        let file = try directory.file("Peel/removals.json", contents: Data("not json".utf8))
        try directory.setPermissions(0, of: file)
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o644],
                ofItemAtPath: file.path(percentEncoded: false)
            )
        }

        await #expect(throws: CommandFailure.self) {
            try await (command(["history"]) as HistoryCommand)
                .run(in: logs.removals, refusals: logs.refusals, trash: movesNothing)
        }
        await #expect(throws: CommandFailure.self) {
            try await (command(["restore", "abcd", "-y"]) as RestoreCommand).run(in: logs.removals, using: service(in: directory))
        }
    }

    @Test func refusesToListRefusalsItCannotRead() async throws {
        let directory = try TemporaryDirectory()
        let logs = logs(in: directory)
        try directory.file("Peel/refusals.json/kept.txt")

        await #expect(throws: CommandFailure.self) { try await printed(["history", "--refused"], from: logs) }
        await #expect(throws: CommandFailure.self) { try await printed(["history", "--refused", "--json"], from: logs) }
    }

    @Test func putsNothingBackWhileTheExclusionsCannotBeRead() async throws {
        let directory = try TemporaryDirectory()
        let logs = logs(in: directory)
        let removal = try removal(in: directory)
        _ = await logs.removals.add([removal.record])

        await #expect(throws: AppLookup.Failure.self) {
            try await (command(["restore", String(removal.record.batch.uuidString.prefix(8)), "-y"]) as RestoreCommand)
                .run(in: logs.removals, using: TrashService(exclusions: .unreadable))
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

    /// An item in the Trash of a disk that isn't connected is still there to put back, so the command asks for the
    /// disk rather than say nothing is left.
    @Test func asksForTheDiskAnItemWaitsOn() async throws {
        let directory = try TemporaryDirectory()
        let logs = logs(in: directory)
        let record = RemovalRecord(
            batch: UUID(),
            item: TrashedItem(
                originalURL: URL(filePath: "/Volumes/org.example.Missing/Report.pdf"),
                trashedURL: URL(filePath: "/Volumes/org.example.Missing/.Trashes/501/Report.pdf"),
                date: .now
            ),
            size: 10, source: "Editor", tool: "applications"
        )
        _ = await logs.removals.add([record])

        let failure = await #expect(throws: CommandFailure.self) {
            try await (command(["restore", String(record.batch.uuidString.prefix(8)), "-y"]) as RestoreCommand)
                .run(in: logs.removals, using: service(in: directory))
        }
        let asked = "1 item is on a disk that isn't connected. Connect it and run the command again."
        #expect(failure?.description == asked)
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
