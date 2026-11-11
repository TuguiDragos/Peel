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

    /// What `arguments` write to standard error.
    private func noted(
        _ arguments: [String],
        from logs: (removals: RemovalLog, refusals: RefusalLog)
    ) async throws -> String {
        let collected = Output.Collected()
        try await Output.$collected.withValue(collected) {
            try await (command(arguments) as HistoryCommand)
                .run(in: logs.removals, refusals: logs.refusals, trash: movesNothing)
        }
        return collected.notes
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

    @Test func namesTheFirstPagesOfALongRemovalAndCountsTheRest() async throws {
        let directory = try TemporaryDirectory()
        let logs = logs(in: directory)
        let batch = UUID()
        let now = Date.now
        let records = (1...30).map { index in
            RemovalRecord(
                batch: batch,
                item: TrashedItem(
                    originalURL: directory.url.appending(path: "home/project\(index)/node_modules"),
                    trashedURL: directory.url.appending(path: "home/.Trash/node_modules \(index)"),
                    date: now.addingTimeInterval(Double(index))
                ),
                size: 10,
                source: "project\(index)",
                tool: "projects"
            )
        }
        _ = await logs.removals.add(records)

        let named = HistoryCommand.rows(for: Batch.all(in: records))[1][2]
        #expect(named == "project1, project2, project3, project4, and 26 more pages")

        let removal = try #require(try listed(try await printed(["history", "--json"], from: logs)).first as? [String: Any])
        #expect((removal["parts"] as? [[String: Any]])?.count == 30)
        #expect((removal["source"] as? String)?.hasSuffix(", and project30") == true)
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
        _ = await logs.removals.add([RemovalJournal.Entry(writer: writer, batch: UUID(), item: item).recordToTakeIn])

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

    @Test func saysWhatHistoryNoLongerListsWhereTheListEnds() async throws {
        let directory = try TemporaryDirectory()
        let removals = RemovalLog(url: directory.url.appending(path: "Peel/removals.json"), flush: { _ in true }, readLimit: 4_096)
        let logs = (removals: removals, refusals: RefusalLog(url: directory.url.appending(path: "Peel/refusals.json")))
        let count = 12
        for index in 0..<count {
            let name = "書類書類書類書類書類書類 \(index)"
            _ = await removals.add([RemovalRecord(
                batch: UUID(),
                item: TrashedItem(
                    originalURL: URL(filePath: "/Users/me/\(name)"),
                    trashedURL: URL(filePath: "/Users/me/.Trash/\(name)"),
                    date: Date(timeIntervalSince1970: Double(index) * 60)
                ),
                size: 1,
                source: "Editor",
                tool: "applications"
            )])
        }
        let listed = Batch.all(in: try #require(await removals.load().records)).count
        try #require(listed > 1 && listed < count)
        let leftOut = Output.count(count - listed, "older removal", "older removals")
        let limit = Output.number(RemovalLog.maximumRecords)
        let note = "History no longer lists \(leftOut): it keeps only its latest removals, up to \(limit) items. What the older ones moved is still in the Trash unless you emptied it.\n"

        #expect(try await noted(["history"], from: logs) == note)
        #expect(try await noted(["history", "--json"], from: logs) == note)
        #expect(try await noted(["history", "--limit", "\(listed - 1)"], from: logs).isEmpty)
    }

    @Test func anEmptiedHistoryIsNotCalledNeverUsed() async throws {
        let directory = try TemporaryDirectory()
        let logs = logs(in: directory)
        let added = await logs.removals.add([try removal(in: directory).record])
        _ = await logs.removals.remove(Set(try #require(added.records).map(\.id)))

        #expect(try await printed(["history"], from: logs) == "History lists no removals.\n")
    }

    @Test func saysHowManyRemovalsAlsoHaveItemsThatStayed() async throws {
        let directory = try TemporaryDirectory()
        let logs = logs(in: directory)
        let earlier = Date.now.addingTimeInterval(-120)
        func moved(_ name: String, at date: Date) -> RemovalRecord {
            RemovalRecord(
                batch: UUID(),
                item: TrashedItem(
                    originalURL: URL(filePath: "/Users/me/\(name)"),
                    trashedURL: URL(filePath: "/Users/me/.Trash/\(name)"),
                    date: date
                ),
                size: 1,
                source: "Editor",
                tool: "applications"
            )
        }
        _ = await logs.removals.add([moved("old.bin", at: earlier)])
        _ = await logs.removals.add([moved("new.bin", at: .now)])
        let stayed = TrashFailure(url: URL(filePath: "/Users/me/kept.bin"), reason: .guarded(.excluded))
        await logs.refusals.add([stayed], source: "Editor", tool: "applications", date: earlier)
        let note = "1 removal also has items that stayed. See `peel history --refused`.\n"

        #expect(try await noted(["history"], from: logs) == note)
        #expect(try await noted(["history", "--json"], from: logs) == note)
        #expect(try await noted(["history", "--limit", "1"], from: logs).isEmpty)
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

    @Test func printsWhatMacOSReportedInEnglishWhateverLanguageWroteIt() async throws {
        let directory = try TemporaryDirectory()
        let logs = logs(in: directory)
        let romanian = "Operația nu a putut fi efectuată. Sistem de fișiere doar citire"
        let error = SystemError(domain: NSPOSIXErrorDomain, code: Int(EROFS))
        await logs.refusals.add(
            [TrashFailure(url: URL(filePath: "/Volumes/Old/report.pdf"), reason: .failed(romanian), error: error)],
            source: "Editor", tool: "applications"
        )

        let text = try await printed(["history", "--refused"], from: logs)
        let json = try await printed(["history", "--refused", "--json"], from: logs)

        #expect(text.contains("Read-only file system") && !text.contains("Operația"))
        #expect(json.contains("Read-only file system") && !json.contains("Operația"))
    }

    @Test func clearsACopySetAsideWhenNothingElseIsLeft() async throws {
        let directory = try TemporaryDirectory()
        let logs = logs(in: directory)
        try directory.file("Peel/refusals-damaged-2026-10-01-090000.json", contents: Data("[".utf8))
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

        #expect(try FileManager.default.contentsOfDirectory(atPath: trash.path(percentEncoded: false)) == ["refusals-damaged-2026-10-01-090000.json"])
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

        let failure = await #expect(throws: CommandFailure.self) { try await printed(["history", "--refused"], from: logs) }
        await #expect(throws: CommandFailure.self) { try await printed(["history", "--refused", "--json"], from: logs) }
        #expect(failure?.description.contains("`peel history --refused --clear`") == true)
        #expect(failure?.description.hasSuffix(" Something other than a file, such as a folder, is where the file should be.") == true)
    }

    @Test func putsNothingBackWhileTheExclusionsCannotBeRead() async throws {
        let directory = try TemporaryDirectory()
        let logs = logs(in: directory)
        let removal = try removal(in: directory)
        _ = await logs.removals.add([removal.record])

        await #expect(throws: AppLookup.Failure.self) {
            try await (command(["restore", String(removal.record.batch.uuidString.prefix(8)), "-y"]) as RestoreCommand)
                .run(in: logs.removals, using: TrashService(exclusions: .unreadable(because: nil)))
        }
    }

    @Test func aRemovalPutBackBringsBackTheFolderItSatInFromAnother() async throws {
        let directory = try TemporaryDirectory()
        let logs = logs(in: directory)
        let support = try directory.directory("home/Library/Application Support")
        _ = try directory.file("home/.Trash/Notes/notes.db")
        try directory.directory("home/.Trash/Example")
        try directory.setPermissions(0o700, of: "home/.Trash/Example")
        let trash = directory.url.appending(path: "home/.Trash")
        let inside = RemovalRecord(
            batch: UUID(),
            item: TrashedItem(
                originalURL: support.appending(path: "Example/Notes"), trashedURL: trash.appending(path: "Notes"),
                date: .now
            ),
            size: 0, source: "Notes", tool: "applications"
        )
        let folder = RemovalRecord(
            batch: UUID(),
            item: TrashedItem(
                originalURL: support.appending(path: "Example"), trashedURL: trash.appending(path: "Example"), date: .now
            ),
            size: 0, source: "Notes", tool: "applications"
        )
        _ = await logs.removals.add([inside, folder])

        try await (command(["restore", String(inside.batch.uuidString.prefix(8)), "-y"]) as RestoreCommand)
            .run(in: logs.removals, using: service(in: directory))

        var info = stat()
        #expect(stat(support.appending(path: "Example").path(percentEncoded: false), &info) == 0)
        #expect(info.st_mode & 0o777 == 0o700)
        #expect(FileManager.default.fileExists(atPath: support.appending(path: "Example/Notes/notes.db").path(percentEncoded: false)))
        #expect(await logs.removals.load().records?.isEmpty == true)
    }

    @Test func saysWhatHistoryKeptAsideWhoeverSetItAside() async throws {
        let directory = try TemporaryDirectory()
        let logs = logs(in: directory)
        _ = try directory.file("Peel/removals.json", contents: Data("[]".utf8))
        let copy = try directory.file("Peel/removals-damaged-2026-11-09-231205.json", contents: Data("{".utf8))

        let notes = try await noted(["history"], from: logs)

        #expect(notes.contains("Peel kept a copy of History it couldn't read as \(Output.path(copy))."))
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

    private func restoring(
        _ record: RemovalRecord, _ flag: String, from logs: (removals: RemovalLog, refusals: RefusalLog),
        in directory: borrowing TemporaryDirectory
    ) async throws -> (said: String, failure: (any Error)?) {
        let service = service(in: directory)
        let collected = Output.Collected()
        let command: RestoreCommand = try command(["restore", String(record.batch.uuidString.prefix(8)), flag])
        let failure = await Output.$collected.withValue(collected) { () async -> (any Error)? in
            do {
                try await command.run(in: logs.removals, using: service)
                return nil
            } catch {
                return error
            }
        }
        return (collected.output + collected.notes, failure)
    }

    @Test(.permissionsHold) func aRestoreDoesNotCallGoneWhatPeelCannotLookAt() async throws {
        let directory = try TemporaryDirectory()
        let logs = logs(in: directory)
        let taken = try removal(in: directory)
        let locked = try directory.file("home/.Trash/locked/report.pdf")
        let unseen = RemovalRecord(
            batch: taken.record.batch,
            item: TrashedItem(
                originalURL: directory.url.appending(path: "home/Documents/other.pdf"), trashedURL: locked, date: .now
            ),
            size: 16, source: "Editor", tool: "applications"
        )
        _ = await logs.removals.add([taken.record, unseen])
        try directory.setPermissions(0, of: "home/.Trash/locked")
        defer { try? directory.setPermissions(0o755, of: "home/.Trash/locked") }

        let part = try await restoring(taken.record, "--dry-run", from: logs, in: directory)
        #expect(part.said.contains("1 item Peel can't look at in the Trash right now stays listed."))
        #expect(!part.said.contains("no longer in the Trash"))

        try directory.setPermissions(0o755, of: "home/.Trash/locked")
        try FileManager.default.removeItem(at: taken.record.trashedURL)
        try directory.setPermissions(0, of: "home/.Trash/locked")

        let none = try await restoring(taken.record, "--dry-run", from: logs, in: directory)
        let answered = SystemError(domain: NSPOSIXErrorDomain, code: Int(EACCES)).localizedDescription
        #expect((none.failure as? CommandFailure)?.description
            == "Peel can't look in the Trash right now, so it can't say what could go back. macOS answered: \(answered)")
    }

    @Test func aRestoreFailsWhenAnItemLeftTheTrash() async throws {
        let directory = try TemporaryDirectory()
        let logs = logs(in: directory)
        let taken = try removal(in: directory)
        let emptied = RemovalRecord(
            batch: taken.record.batch,
            item: TrashedItem(
                originalURL: directory.url.appending(path: "home/Documents/notes.txt"),
                trashedURL: directory.url.appending(path: "home/.Trash/notes.txt"), date: .now
            ),
            size: 10, source: "Editor", tool: "applications"
        )
        _ = await logs.removals.add([taken.record, emptied])

        let real = try await restoring(taken.record, "-y", from: logs, in: directory)

        #expect(real.said.contains("Put 1 item back."))
        #expect(real.said.contains("1 item is no longer in the Trash and can't be put back."))
        #expect(real.failure != nil)
    }

    @Test func aRestoreFailsWhenAnItemWaitsOnADiskThatIsNotConnected() async throws {
        let directory = try TemporaryDirectory()
        let logs = logs(in: directory)
        let taken = try removal(in: directory)
        let waiting = RemovalRecord(
            batch: taken.record.batch,
            item: TrashedItem(
                originalURL: URL(filePath: "/Volumes/org.example.Missing/Report.pdf"),
                trashedURL: URL(filePath: "/Volumes/org.example.Missing/.Trashes/501/Report.pdf"),
                date: .now
            ),
            size: 10, source: "Editor", tool: "applications"
        )
        _ = await logs.removals.add([taken.record, waiting])

        let dry = try await restoring(taken.record, "--dry-run", from: logs, in: directory)
        #expect(dry.failure == nil)

        let real = try await restoring(taken.record, "-y", from: logs, in: directory)
        #expect(real.said.contains("Put 1 item back."))
        #expect(real.said.contains("1 item is on a disk that isn't connected."))
        #expect(real.failure != nil)
    }

    @Test func aRestoreMovesTheVersionInItsPlaceToTheTrashFirstAndKeepsItInHistory() async throws {
        let directory = try TemporaryDirectory()
        let logs = logs(in: directory)
        let place = try directory.file("home/Library/LaunchAgents/org.example.edit.plist", contents: Data("edited".utf8))
        let trashed = try directory.file("home/.Trash/org.example.edit.plist", contents: Data("old".utf8))
        let item = TrashedItem(
            originalURL: place, trashedURL: trashed, date: .now, identity: TrashedItem.Identity(ofItemAt: trashed),
            replacedBy: TrashedItem.Identity(ofItemAt: place)
        )
        let record = RemovalRecord(batch: UUID(), item: item, size: 3, source: "org.example.edit", tool: "backgroundItems")
        _ = await logs.removals.add([record])
        let trash = directory.url.appending(path: "home/.Trash")
        let service = TrashService(
            environment: SearchEnvironment(
                homeDirectory: directory.url.appending(path: "home", directoryHint: .isDirectory),
                rootDirectory: directory.url.appending(path: "root", directoryHint: .isDirectory)
            )
        ) { url in
            let destination = trash.appending(path: "edit-\(url.lastPathComponent)")
            try FileManager.default.moveItem(at: url, to: destination)
            return destination
        }
        func run(_ batch: UUID, _ flag: String) async throws -> String {
            let collected = Output.Collected()
            let command: RestoreCommand = try command(["restore", String(batch.uuidString.prefix(8)), flag])
            try await Output.$collected.withValue(collected) {
                try await command.run(in: logs.removals, using: service)
            }
            return collected.output + collected.notes
        }

        let sentence = "the version now in its place goes to the Trash first, and History keeps it"
        let dry = try await run(record.batch, "--dry-run")
        #expect(dry.contains(sentence), "\(dry)")
        #expect(try String(contentsOf: place, encoding: .utf8) == "edited")

        let real = try await run(record.batch, "-y")
        #expect(real.contains("Put 1 item back."), "\(real)")
        #expect(try String(contentsOf: place, encoding: .utf8) == "old")
        let kept = await logs.removals.load().records ?? []
        #expect(kept.map(\.originalURL) == [place])
        #expect(kept.first?.replacedBy == TrashedItem.Identity(ofItemAt: place))
        #expect(try kept.first.map { try String(contentsOf: $0.trashedURL, encoding: .utf8) } == "edited")
        let back = try await run(try #require(kept.first).batch, "--dry-run")
        #expect(back.contains(sentence), "\(back)")
    }

    @Test func saysSoWhenEverythingLeftIsRefused() async throws {
        let directory = try TemporaryDirectory()
        let logs = logs(in: directory)
        let taken = try removal(in: directory)
        try directory.file("home/Documents/report.pdf", bytes: 1)
        _ = await logs.removals.add([taken.record])

        let dry = try await restoring(taken.record, "--dry-run", from: logs, in: directory)
        let real = try await restoring(taken.record, "-y", from: logs, in: directory)

        let nothing = "Nothing of that removal can be put back from here."
        #expect(dry.said.contains(nothing))
        #expect(!dry.said.contains("Dry run"))
        #expect(dry.failure == nil)
        #expect(real.said.contains(nothing))
        #expect(real.failure != nil)
    }

    @Test(.permissionsHold) func putsNothingBackWhileHistoryCannotBeWritten() async throws {
        let directory = try TemporaryDirectory()
        let logs = logs(in: directory)
        let taken = try removal(in: directory)
        _ = await logs.removals.add([taken.record])
        try directory.setPermissions(0o500, of: "Peel")
        defer { try? directory.setPermissions(0o755, of: "Peel") }

        let answer = try await restoring(taken.record, "-y", from: logs, in: directory)

        #expect((answer.failure as? CommandFailure)?.description.contains("History can't be written") == true)
        #expect(!FileManager.default.fileExists(atPath: taken.original.path(percentEncoded: false)))
    }

    @Test func saysHowManyRemovalsNotMovedNoLongerLists() async throws {
        let directory = try TemporaryDirectory()
        let logs = logs(in: directory)
        await logs.refusals.add(
            [TrashFailure(url: URL(filePath: "/Users/me/kept.bin"), reason: .guarded(.excluded))],
            source: "Editor", tool: "applications"
        )
        RemovalTotals.change(at: RemovalTotals.url(beside: logs.refusals.url)) {
            $0.countRefusalsNoLongerListed(2)
        }

        let limit = Output.number(RefusalLog.maximumRecords)
        #expect(try await noted(["history", "--refused"], from: logs).contains(
            "The record of refusals no longer lists 2 older removals: it keeps only its latest removals, up to \(limit) items. What the older ones couldn't move stayed where it was."
        ))
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

    @Test func aDryRunNamesWhatCannotGoBackAndWhy() async throws {
        let directory = try TemporaryDirectory()
        let logs = logs(in: directory)
        let taken = try removal(in: directory)
        try directory.file("home/Documents/report.pdf", bytes: 1)
        func record(_ name: String) -> RemovalRecord {
            RemovalRecord(
                batch: taken.record.batch,
                item: TrashedItem(
                    originalURL: directory.url.appending(path: "home/Documents/\(name)"),
                    trashedURL: directory.url.appending(path: "home/.Trash/\(name)"),
                    date: .now
                ),
                size: 10, source: "Editor", tool: "applications"
            )
        }
        try directory.file("home/.Trash/letter.txt", bytes: 10)
        _ = await logs.removals.add([taken.record, record("letter.txt"), record("notes.txt")])
        let collected = Output.Collected()

        try await Output.$collected.withValue(collected) {
            try await (command(["restore", String(taken.record.batch.uuidString.prefix(8)), "--dry-run"]) as RestoreCommand)
                .run(in: logs.removals, using: service(in: directory))
        }

        #expect(collected.output.contains("letter.txt"))
        #expect(!collected.output.contains("report.pdf"))
        #expect(collected.notes.contains("report.pdf stays: something is there already"))
        #expect(collected.notes.contains("1 item is no longer in the Trash and can't be put back."))
    }

    @Test(.permissionsHold) func aDryRunLeavesWhatNeedsAnAdministratorOutOfThePlan() async throws {
        let directory = try TemporaryDirectory()
        let logs = logs(in: directory)
        let taken = try removal(in: directory)
        try directory.directory("home/Library/Caches/Locked")
        try directory.file("home/.Trash/daemon.plist", bytes: 10)
        let locked = RemovalRecord(
            batch: taken.record.batch,
            item: TrashedItem(
                originalURL: directory.url.appending(path: "home/Library/Caches/Locked/daemon.plist"),
                trashedURL: directory.url.appending(path: "home/.Trash/daemon.plist"),
                date: .now
            ),
            size: 10, source: "Editor", tool: "applications"
        )
        _ = await logs.removals.add([taken.record, locked])
        try directory.setPermissions(0o500, of: "home/Library/Caches/Locked")
        defer { try? directory.setPermissions(0o755, of: "home/Library/Caches/Locked") }
        let collected = Output.Collected()

        try await Output.$collected.withValue(collected) {
            try await (command(["restore", String(taken.record.batch.uuidString.prefix(8)), "--dry-run"]) as RestoreCommand)
                .run(in: logs.removals, using: service(in: directory))
        }

        #expect(collected.output.contains("report.pdf"))
        #expect(!collected.output.contains("daemon.plist"))
        #expect(collected.notes.contains("daemon.plist stays: it needs administrator access, so put it back with the Peel app"))
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
