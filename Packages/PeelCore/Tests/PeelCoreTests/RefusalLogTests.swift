import Foundation
@testable import PeelCommandLine
@testable import PeelCore
import Testing

struct RefusalLogTests {
    private func failure(_ path: String, _ reason: TrashFailure.Reason) -> TrashFailure {
        TrashFailure(url: URL(filePath: path), reason: reason)
    }

    @Test func writesWhatStayedAndWhy() async throws {
        let directory = try TemporaryDirectory()
        let log = RefusalLog(url: directory.url.appending(path: "Peel/refusals.json"))

        await log.add(
            [failure("/Users/me/Library/Mail", .protectedLocation), failure("/Users/me/x.bin", .failed("no such file"))],
            source: "Editor",
            tool: "applications"
        )

        let records = await RefusalLog(url: log.url).load()
        #expect(records.count == 2)
        #expect(records.allSatisfy { $0.source == "Editor" && $0.tool == "applications" })
        #expect(Set(records.map(\.reason)) == ["protected-location", "failed"])
        #expect(records.first { $0.reason == "failed" }?.detail == "no such file")
        #expect(records.first { $0.reason == "protected-location" }?.detail == nil)
    }

    /// History records nothing when nothing moved, but the refusals are still written: a removal where
    /// everything stayed is the one most worth a record.
    @Test func recordsARemovalWhereNothingMoved() async throws {
        let directory = try TemporaryDirectory()
        let log = RemovalLog(url: directory.url.appending(path: "Peel/removals.json"))
        let refusals = RefusalLog(url: directory.url.appending(path: "Peel/refusals.json"))
        let result = TrashResult(failures: [failure("/Users/me/Library/Mail", .protectedLocation)])

        #expect(await Removals.record(result, from: "Editor", sizes: [:], tool: "applications", in: log, refusals: refusals))

        #expect(await RemovalLog(url: log.url).load().records?.isEmpty == true)
        #expect(await RefusalLog(url: refusals.url).load().map(\.reason) == ["protected-location"])
    }

    @Test func nothingIsWrittenWhenNothingWasRefused() async throws {
        let directory = try TemporaryDirectory()
        let url = directory.url.appending(path: "Peel/refusals.json")

        await RefusalLog(url: url).add([], source: "Editor", tool: "applications")

        #expect(!FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
    }

    @Test func keepsTheNewestAndDropsTheOldest() async throws {
        let directory = try TemporaryDirectory()
        let log = RefusalLog(url: directory.url.appending(path: "refusals.json"))
        let older = (0..<RefusalLog.maximumRecords).map { failure("/Users/me/old-\($0)", .lastCopy) }

        await log.add(older, source: "Old", tool: "duplicates")
        await log.add([failure("/Users/me/new", .notPermitted)], source: "New", tool: "space")

        let records = await log.load()
        #expect(records.count == RefusalLog.maximumRecords)
        #expect(records.contains { $0.source == "New" })
    }

    /// The file is Peel's, but any process the user runs can rewrite it.
    @Test func aRowThatMakesNoSenseCostsThatRowAlone() async throws {
        let directory = try TemporaryDirectory()
        let url = try directory.directory("Peel").appending(path: "refusals.json")
        let good = """
            {"id":"\(UUID().uuidString)","url":"file:///Users/me/a","reason":"last-copy",\
            "date":"2026-09-20T10:00:00Z","source":"Editor","tool":"applications"}
            """
        try Data("[\(good), {\"id\":\"not a uuid\"}]".utf8).write(to: url)

        let records = await RefusalLog(url: url).load()

        #expect(records.map(\.reason) == ["last-copy"])
        #expect(try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path(percentEncoded: false))
            .contains { $0.contains("damaged") }, "the file it could not read was thrown away")
    }

    /// The file is the only copy of what was refused, so when it cannot be read it is never written over.
    @Test func whatCannotBeReadIsKept() async throws {
        let directory = try TemporaryDirectory()
        let url = try directory.directory("Peel").appending(path: "refusals.json")
        try Data("[]".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: url.path(percentEncoded: false))
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path(percentEncoded: false)) }

        await RefusalLog(url: url).add([failure("/Users/me/a", .lastCopy)], source: "Editor", tool: "applications")

        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path(percentEncoded: false))
        #expect(try Data(contentsOf: url) == Data("[]".utf8), "an unreadable record was written over")
    }

    @Test func clearForgetsEverything() async throws {
        let directory = try TemporaryDirectory()
        let log = RefusalLog(url: directory.url.appending(path: "Peel/refusals.json"))
        await log.add([failure("/Users/me/a", .lastCopy)], source: "Editor", tool: "applications")

        #expect(await log.clear())
        #expect(await log.load().isEmpty)
        #expect(await log.clear(), "forgetting what is already forgotten is no failure")
    }

    private static let everyReason: [TrashFailure.Reason] = [
        .protectedLocation, .changedSinceScan, .claimedSinceScan, .lastCopy, .notPermitted, .needsHelper,
        .movedWithoutATrace, .somethingElseMoved(named: "x 2"), .failed("x"),
    ]

    /// A record stores its reason as a word, not a sentence, so a later version of Peel can still read it.
    @Test func everyReasonHasAWordOfItsOwn() {
        let reasons = Self.everyReason

        #expect(Set(reasons.map(\.name)).count == reasons.count)
        #expect(reasons.allSatisfy { !$0.name.contains(" ") })
        #expect(reasons.filter { $0.detail != nil }.count == 2)
    }

    /// History words a refusal from the reason it stored, so every word leads back to its reason, and a word a
    /// later version wrote is read as none rather than guessed at.
    @Test func everyReasonReadsBackFromItsWord() {
        for reason in Self.everyReason {
            #expect(TrashFailure.Reason(name: reason.name, detail: reason.detail) == reason)
        }
        #expect(TrashFailure.Reason(name: "a-word-from-later", detail: nil) == nil)
    }

    /// What one removal refused shares a batch and its source, so History shows it as one entry, in the words of
    /// the source Peel named.
    @Test func oneRemovalsRefusalsShareABatch() async throws {
        let directory = try TemporaryDirectory()
        let log = RefusalLog(url: directory.url.appending(path: "Peel/refusals.json"))

        await log.add([failure("/Users/me/a", .lastCopy), failure("/Users/me/b", .lastCopy)], source: "Duplicates", sourceKey: "tool", tool: "duplicates")
        await log.add([failure("/Users/me/c", .notPermitted)], source: "Editor", tool: "applications")

        let records = await log.load()
        let first = records.filter { $0.source == "Duplicates" }
        #expect(first.count == 2)
        #expect(Set(first.map(\.batch)).count == 1)
        #expect(first.allSatisfy { $0.batch != nil && $0.sourceKey == "tool" })
        #expect(records.first { $0.source == "Editor" }?.batch != first.first?.batch)
        #expect(records.first { $0.source == "Editor" }?.sourceKey == nil)
    }

    /// History lists what was refused one removal to an entry, newest first. A record kept without a batch is an
    /// entry of its own.
    @Test func historyShowsEachRemovalsRefusalsAsOneEntry() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let batch = UUID()
        let stored = """
            [{"id":"\(UUID())","batch":"\(batch)","url":"file:///Users/me/b","reason":"last-copy","date":"2026-09-20T10:00:00Z","source":"Duplicates","sourceKey":"tool","tool":"duplicates"},
             {"id":"\(UUID())","batch":"\(batch)","url":"file:///Users/me/a","reason":"last-copy","date":"2026-09-20T10:00:01Z","source":"Duplicates","sourceKey":"tool","tool":"duplicates"},
             {"id":"\(UUID())","url":"file:///Users/me/old","reason":"not-permitted","date":"2026-09-19T10:00:00Z","source":"Editor","tool":"applications"}]
            """
        let groups = RefusalRecord.grouped(try decoder.decode([RefusalRecord].self, from: Data(stored.utf8)))

        #expect(groups.map(\.source) == ["Duplicates", "Editor"])
        #expect(groups.first?.id == batch)
        #expect(groups.first?.sourceKey == "tool")
        #expect(groups.first?.records.map(\.url.lastPathComponent) == ["a", "b"])
        #expect(groups.first?.date == ISO8601DateFormatter().date(from: "2026-09-20T10:00:00Z"))
        #expect(groups.last?.records.count == 1)
        #expect(groups.last?.sourceKey == nil)
    }
}
