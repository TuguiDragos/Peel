import Foundation
@testable import PeelCore
import Testing

struct RemovalTotalsTests {
    private func record(_ path: String, size: Int64?, batch: UUID) -> RemovalRecord {
        let url = URL(filePath: path)
        return RemovalRecord(
            batch: batch,
            item: TrashedItem(
                originalURL: url,
                trashedURL: URL(filePath: "/Users/x/.Trash").appending(path: url.lastPathComponent),
                date: .now
            ),
            size: size,
            source: "Example",
            tool: "applications"
        )
    }

    @Test func countsWhatEitherProcessRecords() async throws {
        let directory = try TemporaryDirectory()
        let history = directory.url.appending(path: "Peel/removals.json")
        let app = RemovalLog(url: history)
        let commandLine = RemovalLog(url: history)

        _ = await app.add([record("/Applications/Example.app", size: 300, batch: UUID())])
        _ = await commandLine.add([record("/Users/x/Library/Caches/org.example.tool", size: 200, batch: UUID())])

        let totals = RemovalTotals.read(beside: history)
        #expect(totals.bytes == SizeTotal(known: 500, isComplete: true))
        #expect(totals.items == 2)
        #expect(totals.apps == 1)
        #expect(totals.biggest == SizeTotal(known: 300, isComplete: true))
    }

    @Test func aRemovalRecordedPartByPartIsOneRemovalForTheBiggest() async throws {
        let directory = try TemporaryDirectory()
        let history = directory.url.appending(path: "Peel/removals.json")
        let log = RemovalLog(url: history)
        let pass = UUID()

        _ = await log.add([record("/Users/x/Library/Caches/org.example.one", size: 100, batch: pass)])
        _ = await log.add([record("/Users/x/Library/Caches/org.example.two", size: 200, batch: pass)])
        _ = await log.add([record("/Users/x/Library/Caches/org.example.three", size: 250, batch: UUID())])

        let totals = RemovalTotals.read(beside: history)
        #expect(totals.bytes.known == 550)
        #expect(totals.biggest == SizeTotal(known: 300, isComplete: true))
    }

    @Test func anItemNotMeasuredLeavesTheTotalTheLeastItCanBe() async throws {
        let directory = try TemporaryDirectory()
        let history = directory.url.appending(path: "Peel/removals.json")

        _ = await RemovalLog(url: history).add([
            record("/Users/x/Library/Caches/org.example.one", size: 100, batch: UUID()),
            record("/Users/x/Library/Caches/org.example.two", size: nil, batch: UUID()),
        ])

        let totals = RemovalTotals.read(beside: history)
        #expect(totals.bytes == SizeTotal(known: 100, isComplete: false))
        #expect(totals.items == 2)
    }

    @Test func theBiggestRemovalIsTheLeastItCanBeWhicheverPartWasNotMeasured() {
        for sizes in [[1_000, nil], [nil, 1_000]] as [[Int64?]] {
            var totals = RemovalTotals()
            let batch = UUID()
            totals.add(sizes.enumerated().map {
                record("/Users/x/Library/Caches/org.example.\($0.offset)", size: $0.element, batch: batch)
            })
            #expect(totals.biggest == SizeTotal(known: 1_000, isComplete: false))
            #expect(totals.biggest == totals.bytes)
        }
        var kept = RemovalTotals(
            bytes: SizeTotal(known: 1_000, isComplete: true), items: 1, apps: 0,
            biggest: SizeTotal(known: 1_000, isComplete: true)
        )
        kept.takeIn(RemovalTotals(
            bytes: SizeTotal(known: 1_000, isComplete: false), items: 2, apps: 0,
            biggest: SizeTotal(known: 1_000, isComplete: false)
        ))
        #expect(kept.biggest == SizeTotal(known: 1_000, isComplete: false))
    }

    @Test func countsAppsByTheBundlesThatMoved() async throws {
        let directory = try TemporaryDirectory()
        let history = directory.url.appending(path: "Peel/removals.json")
        let batch = UUID()

        _ = await RemovalLog(url: history).add([
            record("/Applications/Example.app", size: 10, batch: batch),
            record("/Applications/Other.app", size: 10, batch: batch),
            record("/Users/x/Library/Application Support/Example/Helper.app", size: 10, batch: batch),
        ])

        #expect(RemovalTotals.read(beside: history).apps == 2)
    }

    @Test func aRemovalCutShortCountsOnceHistoryTakesItIn() async throws {
        let directory = try TemporaryDirectory()
        let history = directory.url.appending(path: "Peel/removals.json")
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/true")
        try process.run()
        process.waitUntilExit()
        let moved = TrashedItem(
            originalURL: URL(filePath: "/Users/x/Library/Caches/org.example.app"),
            trashedURL: URL(filePath: "/Users/x/.Trash/org.example.app"),
            date: .now
        )
        RemovalJournal(beside: history).note(
            [moved],
            batch: UUID(),
            by: RemovalJournal.Writer(pid: process.processIdentifier, started: 1)
        )

        _ = await RemovalLog(url: history).load()

        let totals = RemovalTotals.read(beside: history)
        #expect(totals.items == 1)
        #expect(totals.bytes == SizeTotal(known: 0, isComplete: false))
    }

    @Test func nothingRecordedCountsNothing() async throws {
        let directory = try TemporaryDirectory()
        let history = directory.url.appending(path: "Peel/removals.json")

        _ = await RemovalLog(url: history).add([])

        #expect(RemovalTotals.read(beside: history) == RemovalTotals())
    }

    @Test func takesInTotalsKeptBeforeOnce() async throws {
        let directory = try TemporaryDirectory()
        let history = directory.url.appending(path: "Peel/removals.json")
        let log = RemovalLog(url: history)
        _ = await log.add([record("/Users/x/Library/Caches/org.example.tool", size: 200, batch: UUID())])
        let earlier = RemovalTotals(
            bytes: SizeTotal(known: 1_000, isComplete: false),
            items: 7,
            apps: 2,
            biggest: SizeTotal(known: 900, isComplete: true)
        )

        #expect(await log.takeIn(earlier))
        #expect(await log.takeIn(earlier))

        let totals = RemovalTotals.read(beside: history)
        #expect(totals.bytes == SizeTotal(known: 1_200, isComplete: false))
        #expect(totals.items == 8)
        #expect(totals.apps == 2)
        #expect(totals.biggest == SizeTotal(known: 900, isComplete: true))
    }

    @Test func setsAsideTotalsItCannotRead() async throws {
        let directory = try TemporaryDirectory()
        let history = directory.url.appending(path: "Peel/removals.json")
        let file = history.deletingLastPathComponent().appending(path: "totals.json")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not the totals".utf8).write(to: file)

        _ = await RemovalLog(url: history).add([record("/Users/x/Library/Caches/org.example.tool", size: 200, batch: UUID())])

        #expect(RemovalTotals.read(beside: history).items == 1)
        let kept = try FileManager.default.contentsOfDirectory(
            atPath: file.deletingLastPathComponent().path(percentEncoded: false)
        )
        #expect(kept.contains { $0.hasPrefix("totals-damaged-") })
    }

    @Test func readsTotalsWrittenBeforeHistoryCountedWhatItLeftOut() throws {
        let directory = try TemporaryDirectory()
        let history = directory.url.appending(path: "Peel/removals.json")
        let earlier = #"{"apps":1,"biggest":{"isComplete":true,"known":300},"bytes":{"isComplete":true,"known":500},"items":2,"tookInEarlier":true}"#
        _ = try directory.file("Peel/totals.json", contents: Data(earlier.utf8))

        let totals = RemovalTotals.read(beside: history)

        #expect(totals.items == 2)
        #expect(totals.bytes == SizeTotal(known: 500, isComplete: true))
        #expect(totals.noLongerListed == 0)
    }

    @Test func historyIsRecordedWhenTheTotalsCannotBeWritten() async throws {
        let directory = try TemporaryDirectory()
        let history = directory.url.appending(path: "Peel/removals.json")
        let file = history.deletingLastPathComponent().appending(path: "totals.json")
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: true)

        let outcome = await RemovalLog(url: history).add([record("/Users/x/Library/Caches/org.example.tool", size: 200, batch: UUID())])

        #expect(outcome.records?.count == 1)
        #expect(RemovalTotals.read(beside: history) == RemovalTotals())
    }

    @Test func twoWritersUnderDifferentLocksLoseNoCount() throws {
        let directory = try TemporaryDirectory()
        try directory.directory("Peel")
        let history = directory.url.appending(path: "Peel/removals.json")
        let record = RemovalRecord(
            batch: UUID(),
            item: TrashedItem(
                originalURL: URL(filePath: "/Users/me/Library/Caches/org.example.cache"),
                trashedURL: URL(filePath: "/Users/me/.Trash/org.example.cache"), date: .now
            ),
            size: 1, source: "Space", tool: "space"
        )

        DispatchQueue.concurrentPerform(iterations: 2) { _ in
            for _ in 0..<200 { RemovalTotals.change(at: RemovalTotals.url(beside: history)) { $0.add([record]) } }
        }

        #expect(RemovalTotals.read(beside: history).items == 400)
    }
}
