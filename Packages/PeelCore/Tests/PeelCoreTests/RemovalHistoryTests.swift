import Foundation
@testable import PeelCore
import Testing

struct RemovalHistoryTests {
    private func record(_ name: String, batch: UUID = UUID(), date: Date = .now, size: Int64 = 100) -> RemovalRecord {
        RemovalRecord(
            batch: batch,
            item: TrashedItem(originalURL: URL(filePath: "/Applications/\(name)"), trashedURL: URL(filePath: "/Users/x/.Trash/\(name)"), date: date),
            size: size,
            source: name,
            tool: "applications"
        )
    }

    /// Every installed copy of Peel keeps its History at this path. Moving it would leave every existing record
    /// where nothing reads it, with no warning.
    @Test func historyStaysWhereItAlwaysWas() throws {
        let support = try #require(FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first)

        #expect(RemovalHistory.defaultURL == support.appending(path: "Peel/removals.json"))
        #expect(RemovalHistory.defaultURL.path(percentEncoded: false).hasSuffix("/Peel/removals.json"))
        #expect(RemovalHistory.refusalsURL == support.appending(path: "Peel/refusals.json"))
        #expect(RemovalHistory.refusalsURL.deletingLastPathComponent() == RemovalHistory.defaultURL.deletingLastPathComponent())
    }

    @Test func keepsRecordsAcrossLoads() async throws {
        let directory = try TemporaryDirectory()
        let log = RemovalLog(url: directory.url.appending(path: "removals.json"))

        #expect(await log.load().records?.isEmpty == true)
        _ = await log.add([record("One.app"), record("Two.app")])
        let loaded = try #require(await log.load().records)
        #expect(loaded.count == 2)
        #expect(Set(loaded.map(\.source)) == ["One.app", "Two.app"])
        #expect(loaded[0].trashedItem.originalURL.lastPathComponent.hasSuffix(".app"))
    }

    /// The log keeps each item's time to the millisecond, since one removal moves every part within a second and
    /// names them in the order they moved. A log written to the second reads as well.
    @Test func aRemovalsPartsKeepTheOrderTheyMovedInOnceTheLogIsReadAgain() async throws {
        let directory = try TemporaryDirectory()
        let url = directory.url.appending(path: "removals.json")
        let older = UUID()
        let stored = """
            [{"id":"\(UUID())","batch":"\(older)","originalURL":"file:///Applications/Old.app","trashedURL":"file:///Users/x/.Trash/Old.app","date":"2026-09-20T10:00:00Z","size":1,"source":"Old.app","tool":"applications"}]
            """
        try Data(stored.utf8).write(to: url)
        let log = RemovalLog(url: url)
        let batch = UUID()
        let moment = Date(timeIntervalSince1970: 1_800_000_000)
        for (offset, source, tool) in [(0.1, "com.gone.app", "orphans"), (0.2, "App Caches", "space"), (0.3, "SwiftTool", "projects"), (0.4, "Duplicates", "duplicates")] {
            let item = TrashedItem(originalURL: URL(filePath: "/Users/x/\(source)"), trashedURL: URL(filePath: "/Users/x/.Trash/\(source)"), date: moment.addingTimeInterval(offset))
            _ = await log.add([RemovalRecord(batch: batch, item: item, size: 1, source: source, tool: tool)])
        }

        let groups = RemovalRecord.grouped(try #require(await RemovalLog(url: url).load().records))

        #expect(groups.first { $0.id == batch }?.parts.map(\.tool) == ["orphans", "space", "projects", "duplicates"])
        #expect(groups.first { $0.id == older }?.date == ISO8601DateFormatter().date(from: "2026-09-20T10:00:00Z"))
    }

    @Test func removesOnlyTheRecordsAskedFor() async throws {
        let directory = try TemporaryDirectory()
        let log = RemovalLog(url: directory.url.appending(path: "removals.json"))
        let kept = record("Kept.app")
        let dropped = record("Dropped.app")
        _ = await log.add([kept, dropped])

        let remaining = try #require(await log.remove([dropped.id]).records)
        #expect(remaining.map(\.id) == [kept.id])
        #expect(await log.load().records?.map(\.id) == [kept.id])
    }

    @Test func keepsTheNewestRecordsWhenTheFileIsFull() {
        let old = (0..<RemovalLog.maximumRecords).map { record("Old\($0).app", date: Date(timeIntervalSince1970: Double($0))) }
        let newest = record("Newest.app", date: Date(timeIntervalSince1970: 10_000_000))

        let trimmed = RemovalLog.trimmed(old + [newest], keeping: [newest.batch])
        #expect(trimmed.count <= RemovalLog.maximumRecords)
        #expect(trimmed.first?.id == newest.id)
        #expect(!trimmed.contains { $0.source == "Old0.app" })
    }

    /// The log on disk uses these field names and ISO 8601 times. Changing either would make every existing log
    /// unreadable.
    @Test func keepsTheStoredShapeOfARecord() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = LogTime.encoding
        let stored = try encoder.encode([record("One.app", date: Date(timeIntervalSince1970: 5.25))])
        let fields = try #require((JSONSerialization.jsonObject(with: stored) as? [[String: Any]])?.first)

        #expect(Set(fields.keys) == ["id", "batch", "originalURL", "trashedURL", "date", "size", "source", "tool"])
        #expect(fields["date"] as? String == "1970-01-01T00:00:05.250Z")

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = LogTime.decoding
        #expect(try decoder.decode([RemovalRecord].self, from: stored).first?.date == Date(timeIntervalSince1970: 5.25))
    }

    /// `removals.json` is a file any process can rewrite, and Swift's `+` traps on overflow, so the sizes read
    /// from it are checked and added up without trapping.
    @Test func aSizeNobodyCouldHaveMeasuredNeitherCrashesNorCounts() throws {
        let stored = """
        [{"id":"\(UUID())","batch":"\(UUID())","originalURL":"file:///Applications/A.app","trashedURL":"file:///Users/x/.Trash/A.app",
          "date":"2026-09-20T10:00:00Z","size":9223372036854775807,"source":"A","tool":"applications"},
         {"id":"\(UUID())","batch":"\(UUID())","originalURL":"file:///Applications/B.app","trashedURL":"file:///Users/x/.Trash/B.app",
          "date":"2026-09-20T10:00:00Z","size":-5,"source":"B","tool":"applications"},
         {"id":"\(UUID())","batch":"\(UUID())","originalURL":"file:///Applications/C.app","trashedURL":"file:///Users/x/.Trash/C.app",
          "date":"2026-09-20T10:00:00Z","size":1,"source":"C","tool":"applications"}]
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let records = try decoder.decode([RemovalRecord].self, from: Data(stored.utf8))

        #expect(records.map(\.size) == [Int64.max, 0, 1], "a size below zero is no size")
        #expect(records.totalSize == SizeTotal(known: .max, isComplete: true), "the sum stops at the largest number there is instead of trapping")
    }

    /// What Peel could not measure is recorded as not known, so History never shows it as zero and a total with
    /// it in says "over". A record written without a size, or with `null`, reads the same way.
    @Test func aSizeNobodyMeasuredStaysUnknown() throws {
        let stored = """
        [{"id":"\(UUID())","batch":"\(UUID())","originalURL":"file:///Applications/A.app","trashedURL":"file:///Users/x/.Trash/A.app",
          "date":"2026-09-20T10:00:00Z","size":null,"source":"A","tool":"applications"},
         {"id":"\(UUID())","batch":"\(UUID())","originalURL":"file:///Applications/B.app","trashedURL":"file:///Users/x/.Trash/B.app",
          "date":"2026-09-20T10:00:00Z","source":"B","tool":"applications"},
         {"id":"\(UUID())","batch":"\(UUID())","originalURL":"file:///Applications/C.app","trashedURL":"file:///Users/x/.Trash/C.app",
          "date":"2026-09-20T10:00:00Z","size":7,"source":"C","tool":"applications"}]
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let records = try decoder.decode([RemovalRecord].self, from: Data(stored.utf8))

        #expect(records.map(\.size) == [nil, nil, 7])
        #expect(records.totalSize == SizeTotal(known: 7, isComplete: false))

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        #expect(try decoder.decode([RemovalRecord].self, from: encoder.encode(records)).map(\.size) == [nil, nil, 7])
    }

    @Test func tellsWhenAnItemIsNoLongerInTheTrash() throws {
        let directory = try TemporaryDirectory()
        let trashed = try directory.file("Something.app/Contents/Info.plist")
        let present = RemovalRecord(
            batch: UUID(),
            item: TrashedItem(originalURL: URL(filePath: "/Applications/Something.app"), trashedURL: trashed, date: .now),
            size: 1,
            source: "Something",
            tool: "applications"
        )
        #expect(present.isStillInTrash)
        #expect(present.isOnAConnectedDisk)
        #expect(!record("Gone.app").isStillInTrash)
        #expect(record("Gone.app").isOnAConnectedDisk)
    }

    /// An item in the Trash of a disk that is not connected may still be there, so its record is kept.
    @Test func tellsWhenTheDiskOfAnItemIsNotConnected() {
        let away = RemovalRecord(
            batch: UUID(),
            item: TrashedItem(
                originalURL: URL(filePath: "/Volumes/PeelNoSuchDisk/Projects/app/node_modules"),
                trashedURL: URL(filePath: "/Volumes/PeelNoSuchDisk/.Trashes/501/node_modules"),
                date: .now
            ),
            size: 1,
            source: "app",
            tool: "projects"
        )
        #expect(!away.isStillInTrash)
        #expect(!away.isOnAConnectedDisk)
    }

    private static func record(batch: UUID, date: Date = .now, name: String = "Item") -> RemovalRecord {
        RemovalRecord(
            batch: batch,
            item: TrashedItem(
                originalURL: URL(filePath: "/Applications/\(name).app"),
                trashedURL: URL(filePath: "/Users/someone/.Trash/\(name).app"),
                date: date
            ),
            size: 1,
            source: name,
            tool: "applications"
        )
    }

    /// The log is the only way back from a removal. A file that cannot be understood must not be written
    /// over: the bytes are kept under another name, and recording carries on.
    @Test func keepsADamagedFileInsteadOfOverwritingIt() async throws {
        let directory = try TemporaryDirectory()
        let url = try directory.file("Peel/removals.json", contents: Data("{ this is not the log }".utf8))
        let log = RemovalLog(url: url)

        let outcome = await log.add([Self.record(batch: UUID())])

        let folder = url.deletingLastPathComponent()
        let setAside = try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))
            .filter { $0.contains("damaged") }
        #expect(setAside.count == 1, "the damaged file was not kept: \(setAside)")
        #expect(outcome.records?.count == 1, "recording did not carry on")
        guard case .damaged = outcome.problem else {
            Issue.record("the damage was not reported: \(String(describing: outcome.problem))")
            return
        }
    }

    /// A row written by a later version, or broken by a hand edit, must not cost the others. The rows that can be
    /// read are kept, after the whole file is saved under another name.
    @Test func keepsTheRowsItCanReadWhenOneMakesNoSense() async throws {
        let directory = try TemporaryDirectory()
        let url = directory.url.appending(path: "Peel/removals.json")
        let healthy = RemovalLog(url: url)
        _ = await healthy.add([record("One.app"), record("Two.app")])
        var rows = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [[String: Any]])
        rows.insert(["id": UUID().uuidString, "source": "a row with most of its fields missing"], at: 1)
        let damaged = try JSONSerialization.data(withJSONObject: rows)
        try damaged.write(to: url)

        let outcome = await RemovalLog(url: url).load()

        #expect(outcome.records?.map(\.source).sorted() == ["One.app", "Two.app"])
        guard case .damaged(let setAside) = outcome.problem else {
            Issue.record("the damage was not reported: \(String(describing: outcome.problem))")
            return
        }
        #expect(try Data(contentsOf: setAside) == damaged, "the file as it was is not what was kept")
        #expect(await RemovalLog(url: url).load().records?.count == 2, "what could be read was not written back")
    }

    /// A full disk is when people run a cleaner, and also when the record cannot be written. History opens by
    /// reading the older, healthy file, and that read must not clear the notice.
    @Test func aRemovalThatCouldNotBeRecordedStaysSaidUntilOneIs() async throws {
        let directory = try TemporaryDirectory()
        let url = try directory.file("Peel/removals.json", contents: Data("[]".utf8))
        let log = RemovalLog(url: url)
        try directory.setPermissions(0o500, of: "Peel")
        defer { try? directory.setPermissions(0o755, of: "Peel") }

        #expect(await log.add([Self.record(batch: UUID())]).problem == .couldNotRecord)
        #expect(await log.load().problem == .couldNotRecord, "reading the older file took the notice away")

        try directory.setPermissions(0o755, of: "Peel")
        #expect(await log.add([Self.record(batch: UUID())]).problem == nil, "a removal that was recorded is what ends it")
    }

    /// A Put Back that cannot update the log reports `couldNotUpdate`, not `couldNotRecord`: nothing was
    /// removed, and the items have left the Trash.
    @Test func aPutBackThatCouldNotBeWrittenDownSaysSo() async throws {
        let directory = try TemporaryDirectory()
        let log = RemovalLog(url: directory.url.appending(path: "Peel/removals.json"))
        let record = Self.record(batch: UUID())
        _ = await log.add([record])
        try directory.setPermissions(0o500, of: "Peel")
        defer { try? directory.setPermissions(0o755, of: "Peel") }

        #expect(await log.remove([record.id]).problem == .couldNotUpdate)
    }

    /// A file that cannot even be read cannot be copied out of the way, so nothing is written at all.
    @Test func leavesAnUnreadableFileAlone() async throws {
        let directory = try TemporaryDirectory()
        let url = try directory.file("Peel/removals.json", contents: Data("[]".utf8))
        try directory.setPermissions(0, of: "Peel/removals.json")
        defer { try? directory.setPermissions(0o644, of: "Peel/removals.json") }

        let outcome = await RemovalLog(url: url).add([Self.record(batch: UUID())])

        #expect(outcome.records == nil, "an unreadable log was replaced anyway")
        #expect(outcome.problem == .unreadable)
    }

    /// A log in a folder that cannot be searched is not known to be empty, so it is unreadable, never replaced.
    @Test func aLogItCannotReachIsUnreadableNotEmpty() async throws {
        let directory = try TemporaryDirectory()
        let url = try directory.file("Peel/removals.json", contents: Data("[]".utf8))
        try directory.setPermissions(0o600, of: "Peel")
        defer { try? directory.setPermissions(0o755, of: "Peel") }

        let outcome = await RemovalLog(url: url).add([Self.record(batch: UUID())])

        #expect(outcome.records == nil)
        #expect(outcome.problem == .unreadable)
    }

    /// History showing "3 items" for a removal that touched twelve is worse than showing nothing: the user
    /// cannot tell which nine are missing. Whole batches are dropped, never part of one.
    @Test func recordsAWholeBatchEvenWhenItIsLargerThanTheCap() async throws {
        let directory = try TemporaryDirectory()
        let url = directory.url.appending(path: "Peel/removals.json")
        let batch = UUID()
        let records = (0..<(RemovalLog.maximumRecords + 500)).map { Self.record(batch: batch, name: "Item\($0)") }

        let outcome = await RemovalLog(url: url).add(records)

        #expect(outcome.records?.count == records.count, "the batch lost its tail")
    }

    @Test func trimsWholeBatchesOnly() throws {
        let old = (0..<3).map { index -> [RemovalRecord] in
            let batch = UUID()
            return (0..<(RemovalLog.maximumRecords / 2)).map {
                Self.record(batch: batch, date: .now.addingTimeInterval(TimeInterval(-10_000 + index)), name: "Old\($0)")
            }
        }
        let newest = UUID()
        let arriving = (0..<10).map { Self.record(batch: newest, name: "New\($0)") }

        let trimmed = RemovalLog.trimmed(old.flatMap { $0 } + arriving, keeping: [newest])

        let counts = Dictionary(grouping: trimmed, by: \.batch).mapValues(\.count)
        #expect(counts[newest] == arriving.count, "the batch being added was trimmed")
        for (batch, count) in counts where batch != newest {
            #expect(count == RemovalLog.maximumRecords / 2, "batch \(batch) was cut in half")
        }
    }

    /// The app and `peel` are two processes writing one file, and an actor keeps order inside one process only.
    /// Two logs on the same file stand in for the two processes.
    @Test func keepsEveryRecordWhenTwoWritersShareTheFile() async throws {
        let directory = try TemporaryDirectory()
        let url = directory.url.appending(path: "removals.json")
        let app = RemovalLog(url: url)
        let tool = RemovalLog(url: url)

        await withTaskGroup(of: Void.self) { group in
            for index in 0..<40 {
                group.addTask { _ = await app.add([Self.record(batch: UUID(), name: "App \(index)")]) }
                group.addTask { _ = await tool.add([Self.record(batch: UUID(), name: "Tool \(index)")]) }
            }
        }

        #expect(await RemovalLog(url: url).load().records?.count == 80)
    }

    @Test func keepsEveryRecordWhenAddsOverlap() async throws {
        let directory = try TemporaryDirectory()
        let log = RemovalLog(url: directory.url.appending(path: "Peel/removals.json"))

        await withTaskGroup(of: Void.self) { group in
            for index in 0..<50 {
                group.addTask { _ = await log.add([Self.record(batch: UUID(), name: "Item\(index)")]) }
            }
        }

        let outcome = await log.load()
        #expect(outcome.records?.count == 50, "kept \(outcome.records?.count ?? -1) of 50")
    }
}
