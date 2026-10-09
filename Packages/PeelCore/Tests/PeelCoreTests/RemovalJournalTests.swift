import Foundation
@testable import PeelCore
import Synchronization
import Testing

struct RemovalJournalTests {
    /// An item that moved at a time with more than milliseconds in it, as every real move has.
    private func item(
        _ name: String,
        in directory: borrowing TemporaryDirectory,
        at date: Date = Date(timeIntervalSince1970: 1_800_000_000.002_07)
    ) -> TrashedItem {
        TrashedItem(
            originalURL: directory.url.appending(path: "home/Library/Caches/\(name)"),
            trashedURL: directory.url.appending(path: "home/.Trash/\(name)"),
            date: date
        )
    }

    /// A process that has ended, which no running process can be taken for.
    private func endedProcess() throws -> RemovalJournal.Writer {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/true")
        try process.run()
        process.waitUntilExit()
        return RemovalJournal.Writer(pid: process.processIdentifier, started: 1)
    }

    private func service(
        in directory: borrowing TemporaryDirectory,
        journal: RemovalJournal,
        moveToTrash: @escaping @Sendable (URL) throws -> URL
    ) -> TrashService {
        TrashService(
            environment: SearchEnvironment(
                homeDirectory: directory.url.appending(path: "home"),
                rootDirectory: directory.url.appending(path: "root")
            ),
            journal: journal,
            moveToTrash: moveToTrash
        )
    }

    /// A removal cut short by a quit or a crash left what it moved in the journal: the next read of History takes it
    /// in, as an interrupted removal, and the journal lets it go.
    @Test func aRemovalCutShortIsInHistoryTheNextTimeItIsRead() async throws {
        let directory = try TemporaryDirectory()
        let history = directory.url.appending(path: "Peel/removals.json")
        let journal = RemovalJournal(beside: history)
        let moved = item("com.example.app", in: directory)
        journal.note([moved], batch: UUID(), by: try endedProcess())

        let records = try #require(await RemovalLog(url: history).load().records)

        #expect(records.map(\.trashedURL) == [moved.trashedURL])
        #expect(records.first?.sourceKey == "interrupted")
        #expect(records.first?.size == nil)
        #expect(journal.entries().isEmpty)
    }

    /// While the process that moved an item still runs, it records the item itself, in its own words: a read of
    /// History meanwhile, from the app or from `peel`, leaves the journal alone.
    @Test func aRemovalStillUnderWayIsLeftToRecordItself() async throws {
        let directory = try TemporaryDirectory()
        let history = directory.url.appending(path: "Peel/removals.json")
        let journal = RemovalJournal(beside: history)
        let moved = item("com.example.app", in: directory)
        journal.note([moved], batch: UUID(), by: .current)

        #expect(await RemovalLog(url: history).load().records?.isEmpty == true)
        #expect(journal.entries().count == 1)

        let record = RemovalRecord(batch: UUID(), item: moved, size: 10, source: "Editor", tool: "applications")
        _ = await RemovalLog(url: history).add([record])

        #expect(journal.entries().isEmpty, "History recorded the item and the journal kept it")
    }

    @Test func historyIsOnTheDriveBeforeTheJournalLetsGo() async throws {
        let directory = try TemporaryDirectory()
        let history = directory.url.appending(path: "Peel/removals.json")
        let journal = RemovalJournal(beside: history)
        let moved = item("com.example.app", in: directory)
        journal.note([moved], batch: UUID(), by: .current)
        let flushed = Mutex<[(path: String, waiting: Int)]>([])
        let log = RemovalLog(url: history) { path in
            flushed.withLock { $0.append((path, journal.entries().count)) }
            return true
        }

        let record = RemovalRecord(batch: UUID(), item: moved, size: 10, source: "Editor", tool: "applications")
        _ = await log.add([record])
        _ = await log.remove([record.id])

        #expect(flushed.withLock { $0.map(\.path) } == [history.path(percentEncoded: false)])
        #expect(flushed.withLock { $0.first?.waiting } == 1, "the journal let the item go before History was on the drive")
    }

    /// An item History already has is never recorded twice, as when a process wrote History and stopped before it
    /// could let the journal go.
    @Test func anItemHistoryHasIsNotRecordedAgain() async throws {
        let directory = try TemporaryDirectory()
        let history = directory.url.appending(path: "Peel/removals.json")
        let journal = RemovalJournal(beside: history)
        let moved = item("com.example.app", in: directory)
        let record = RemovalRecord(batch: UUID(), item: moved, size: 10, source: "Editor", tool: "applications")
        _ = await RemovalLog(url: history).add([record])
        journal.note([moved], batch: UUID(), by: try endedProcess())

        let records = try #require(await RemovalLog(url: history).load().records)

        #expect(records.map(\.id) == [record.id])
        #expect(journal.entries().isEmpty)
    }

    /// An older record at the same places, an item that moved there before and has left the Trash since, is
    /// another item: the one that moved now is still recorded.
    @Test func anOlderItemAtTheSamePlacesIsAnotherItem() async throws {
        let directory = try TemporaryDirectory()
        let history = directory.url.appending(path: "Peel/removals.json")
        let journal = RemovalJournal(beside: history)
        let older = item("com.example.app", in: directory)
        _ = await RemovalLog(url: history).add([RemovalRecord(batch: UUID(), item: older, size: 10, source: "Editor", tool: "applications")])
        let newer = item("com.example.app", in: directory, at: older.date.addingTimeInterval(86_400))
        journal.note([newer], batch: UUID(), by: try endedProcess())

        let records = try #require(await RemovalLog(url: history).load().records)

        #expect(records.count == 2)
        #expect(records.contains { $0.sourceKey == "interrupted" && LogTime.text(for: $0.date) == LogTime.text(for: newer.date) })
    }

    /// Each item is written down as soon as it has moved, before the next one moves and before the service returns,
    /// so a stop at any point loses no more than the item moving then.
    @Test func theServiceWritesDownEachItemAsItMoves() async throws {
        let directory = try TemporaryDirectory()
        let first = try directory.file("home/Library/Caches/com.example.one/cache.db").deletingLastPathComponent()
        let second = try directory.file("home/Library/Caches/com.example.two/cache.db").deletingLastPathComponent()
        let journal = RemovalJournal(beside: directory.url.appending(path: "Peel/removals.json"))
        let written = Mutex<[Int]>([])
        let service = service(in: directory, journal: journal) { url in
            written.withLock { $0.append(journal.entries().count) }
            return directory.url.appending(path: "home/.Trash/\(url.lastPathComponent)")
        }

        let result = await service.trash([first, second])

        #expect(result.trashed.count == 2)
        #expect(written.withLock { $0 } == [0, 1], "the first item was not written down before the second moved")
        #expect(Set(journal.entries().map(\.item.trashedURL)) == Set(result.trashed.map(\.trashedURL)))
    }

    /// While History cannot be read nothing moves, since what moved could not be listed for Put Back. An item the
    /// guard refuses keeps that reason, and Peel's own files, which History never lists, still go.
    @Test(.permissionsHold) func nothingMovesWhileHistoryCannotBeRead() async throws {
        let directory = try TemporaryDirectory()
        let history = try directory.file("home/Library/Application Support/Peel/removals.json", contents: Data("[]".utf8))
        try directory.setPermissions(0, of: "home/Library/Application Support/Peel/removals.json")
        defer { try? directory.setPermissions(0o644, of: "home/Library/Application Support/Peel/removals.json") }
        let item = try directory.file("home/Library/Caches/com.example.app/cache.db").deletingLastPathComponent()
        let keychains = try directory.directory("home/Library/Keychains")
        let moved = Mutex<[URL]>([])
        let service = service(in: directory, journal: RemovalJournal(beside: history)) { url in
            moved.withLock { $0.append(url) }
            return directory.url.appending(path: "home/.Trash/\(url.lastPathComponent)")
        }

        #expect(service.refusal(of: item) == .historyUnreadable)
        #expect(service.refusal(of: keychains) == .guarded(.protectedLocation))
        let result = await service.trash([item, keychains])
        let throughTheHelper = await service.trash([item], usingHelperFor: [item])

        #expect(moved.withLock { $0 }.isEmpty)
        #expect(result.failures.map(\.reason) == [.historyUnreadable, .guarded(.protectedLocation)])
        #expect(throughTheHelper.failures.map(\.reason) == [.historyUnreadable])
        #expect(await service.trashOwnFiles([item]).trashed.count == 1, "Peel's own files waited for History")
    }

    /// Peel's folder holds the journal, and Peel moves it last as it removes itself: that move is not written
    /// down, since History went with the folder and writing the line would make the folder again.
    @Test func theMoveOfTheFolderThatHoldsTheJournalMakesNothingAgain() async throws {
        let directory = try TemporaryDirectory()
        let folder = try directory.directory("home/Library/Application Support/Peel")
        let trash = try directory.directory("home/.Trash")
        let journal = RemovalJournal(beside: folder.appending(path: "removals.json"))
        let service = service(in: directory, journal: journal) { url in
            let landed = trash.appending(path: url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: landed)
            return landed
        }

        let result = await service.trash([folder])

        #expect(result.trashed.map(\.originalURL) == [folder])
        #expect(!FileManager.default.fileExists(atPath: folder.path(percentEncoded: false)), "the folder was made again")
    }

    /// A copy of settings Peel could not finish goes to the Trash as its own file, which History never lists, so
    /// nothing is written down that would come back later as an interrupted removal.
    @Test func aCopyPeelCouldNotFinishIsNotWrittenDown() async throws {
        let directory = try TemporaryDirectory()
        let backups = try directory.directory("home/Library/Application Support/Peel/Preference Backups")
        let journal = RemovalJournal(beside: directory.url.appending(path: "home/Library/Application Support/Peel/removals.json"))
        let moved = Mutex<[URL]>([])
        let service = service(in: directory, journal: journal) { url in
            moved.withLock { $0.append(url) }
            return directory.url.appending(path: "home/.Trash/\(url.lastPathComponent)")
        }
        let app = InstalledApp(url: URL(filePath: "/Applications/Example.app"), bundleIdentifier: "com.example.app", name: "Example")
        let preferences = URL.homeDirectory.appending(path: "Library/Preferences")
        let exports = Mutex(0)

        // The first domain is copied, the second is not, so the copy is left half made.
        let saved = await PreferenceBackup.save(
            [preferences.appending(path: "com.example.app.plist"), preferences.appending(path: "com.example.app.helper.plist")],
            for: app,
            in: backups,
            through: service
        ) { arguments in
            guard arguments.first == "export", let file = arguments.last else { return .yes }
            guard exports.withLock({ $0 += 1; return $0 }) == 1 else { return .no }
            FileManager.default.createFile(atPath: file, contents: Data())
            return .yes
        }

        #expect(saved == .failed)
        #expect(moved.withLock { $0.count } == 1, "the half made copy did not go to the Trash")
        #expect(journal.entries().isEmpty)
    }

    /// A line cut short, as when the disk filled up, costs only itself: the next line starts on a line of its own.
    @Test func aLineCutShortCostsOnlyItself() throws {
        let directory = try TemporaryDirectory()
        let journal = RemovalJournal(beside: directory.url.appending(path: "Peel/removals.json"))
        let moved = item("com.example.app", in: directory)
        try FileManager.default.createDirectory(
            at: journal.url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(#"{"batch":"#.utf8).write(to: journal.url)

        journal.note([moved], batch: UUID())

        #expect(journal.entries().map(\.item.trashedURL) == [moved.trashedURL])
    }

    /// With no journal there is nothing to take in: reading it or letting lines go makes nothing on the disk.
    @Test func withNoJournalNothingIsMade() throws {
        let directory = try TemporaryDirectory()
        let folder = directory.url.appending(path: "Peel")
        let journal = RemovalJournal(beside: folder.appending(path: "removals.json"))

        #expect(journal.entries().isEmpty)
        journal.forget([item("com.example.app", in: directory)])

        #expect(!FileManager.default.fileExists(atPath: folder.path(percentEncoded: false)))
    }

    /// Every place in the Trash Peel put something, from any process: what History records and what a removal under
    /// way has written down so far, as long as that item is still there.
    @Test func knowsWhatPeelPutInTheTrashFromAnyProcess() async throws {
        let directory = try TemporaryDirectory()
        let log = RemovalLog(url: directory.url.appending(path: "Peel/removals.json"))
        let recorded = try directory.directory("Trash/Recorded.app")
        let underWay = try directory.directory("Trash/UnderWay.app")
        let emptied = directory.url.appending(path: "Trash/Emptied.app")
        try directory.directory("Trash/Thrown.app")
        func item(_ trashed: URL) -> TrashedItem {
            let original = URL(filePath: "/Applications/\(trashed.lastPathComponent)")
            return TrashedItem(originalURL: original, trashedURL: trashed, date: .now)
        }
        _ = await log.add([
            RemovalRecord(batch: UUID(), item: item(recorded), size: 1, source: "Recorded", tool: "applications"),
            RemovalRecord(batch: UUID(), item: item(emptied), size: 1, source: "Emptied", tool: "applications"),
        ])
        RemovalJournal(beside: log.url).note([item(underWay)], batch: UUID(), by: .current)

        let places = await log.placesInTheTrash()

        #expect(places == Set([recorded, underWay].map(PathPattern.comparablePath(of:))))
    }

}
