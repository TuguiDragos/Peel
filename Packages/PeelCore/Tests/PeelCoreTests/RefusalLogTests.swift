import Foundation
@testable import PeelCommandLine
@testable import PeelCore
import Testing

struct RefusalLogTests {
    private func failure(_ path: String, _ reason: TrashFailure.Reason) -> TrashFailure {
        TrashFailure(url: URL(filePath: path), reason: reason)
    }

    private func trash(in directory: borrowing TemporaryDirectory) throws -> (service: TrashService, folder: URL) {
        let folder = try directory.directory("Trash")
        let service = TrashService(
            environment: SearchEnvironment(homeDirectory: directory.url, rootDirectory: directory.url)
        ) { url in
            let destination = folder.appending(path: UUID().uuidString + " " + url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: destination)
            return destination
        }
        return (service, folder)
    }

    @Test func writesWhatStayedAndWhy() async throws {
        let directory = try TemporaryDirectory()
        let log = RefusalLog(url: directory.url.appending(path: "Peel/refusals.json"))

        await log.add(
            [
                failure("/Users/me/Library/Mail", .guarded(.protectedLocation)),
                failure("/Users/me/x.bin", .failed("no such file")),
            ],
            source: "Editor",
            tool: "applications"
        )

        let records = try #require(await RefusalLog(url: log.url).load().records)
        #expect(records.count == 2)
        #expect(records.allSatisfy { $0.source == "Editor" && $0.tool == "applications" })
        #expect(Set(records.map(\.reason)) == ["protected-place", "failed"])
        #expect(records.first { $0.reason == "failed" }?.detail == "no such file")
        #expect(records.first { $0.reason == "protected-place" }?.detail == nil)
    }

    /// History records nothing when nothing moved, but the refusals are still written: a removal where
    /// everything stayed is the one most worth a record.
    @Test func recordsARemovalWhereNothingMoved() async throws {
        let directory = try TemporaryDirectory()
        let log = RemovalLog(url: directory.url.appending(path: "Peel/removals.json"))
        let refusals = RefusalLog(url: directory.url.appending(path: "Peel/refusals.json"))
        let result = TrashResult(failures: [failure("/Users/me/Library/Mail", .guarded(.protectedLocation))])

        #expect(await Removals.record(result, from: "Editor", sizes: [:], tool: "applications", in: log, refusals: refusals))

        #expect(await RemovalLog(url: log.url).load().records?.isEmpty == true)
        #expect(await RefusalLog(url: refusals.url).load().records?.map(\.reason) == ["protected-place"])
    }

    /// History is the way back for what just moved, so it is written before the refusals: while the refusal log
    /// waits for another writer, what moved is already in History.
    @Test func writesHistoryBeforeTheRefusals() async throws {
        let directory = try TemporaryDirectory()
        let folder = try directory.directory("Peel")
        let history = folder.appending(path: "removals.json")
        let log = RemovalLog(url: history)
        let refusals = RefusalLog(url: folder.appending(path: "refusals.json"))
        let moved = TrashedItem(
            originalURL: URL(filePath: "/Users/me/Library/Caches/com.example.app"),
            trashedURL: URL(filePath: "/Users/me/.Trash/com.example.app"),
            date: .now
        )
        let result = TrashResult(
            trashed: [moved], failures: [failure("/Users/me/Library/Mail", .guarded(.protectedLocation))]
        )
        // Holds the refusal log's lock, as another process writing it would.
        let lockFile = folder.appending(path: "refusals.json.lock").path(percentEncoded: false)
        let lock = open(lockFile, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
        defer { close(lock) }
        flock(lock, LOCK_EX)

        let recording = Task {
            await Removals.record(result, from: "Editor", sizes: [:], tool: "applications", in: log, refusals: refusals)
        }
        var isInHistory = false
        for _ in 0..<100 where !isInHistory {
            try await Task.sleep(for: .milliseconds(20))
            isInHistory = FileManager.default.fileExists(atPath: history.path(percentEncoded: false))
        }
        flock(lock, LOCK_UN)

        #expect(await recording.value)
        #expect(isInHistory, "History waited for the refusals")
    }

    @Test func nothingIsWrittenWhenNothingWasRefused() async throws {
        let directory = try TemporaryDirectory()
        let url = directory.url.appending(path: "Peel/refusals.json")

        await RefusalLog(url: url).add([], source: "Editor", tool: "applications")

        #expect(!FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
    }

    /// Past its cap the log drops the oldest removals whole, as History does: an entry cut in part would read as
    /// all that was refused.
    @Test func dropsTheOldestRemovalsWhole() async throws {
        let directory = try TemporaryDirectory()
        let log = RefusalLog(url: directory.url.appending(path: "refusals.json"))
        let oldest = (0..<3_000).map { failure("/Users/me/oldest-\($0)", .lastCopy) }
        let older = (0..<2_000).map { failure("/Users/me/older-\($0)", .lastCopy) }

        await log.add(oldest, source: "Oldest", tool: "duplicates", date: .now.addingTimeInterval(-120))
        await log.add(older, source: "Older", tool: "duplicates", date: .now.addingTimeInterval(-60))
        await log.add([failure("/Users/me/new", .notPermitted)], source: "New", tool: "space")

        let records = try #require(await log.load().records)
        #expect(records.count == 2_001)
        #expect(Set(records.map(\.source)) == ["Older", "New"])
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

        let outcome = await RefusalLog(url: url).load()

        #expect(outcome.records?.map(\.reason) == ["last-copy"])
        guard case .damaged(let setAside) = outcome.problem else { Issue.record("no damage reported"); return }
        #expect(setAside.lastPathComponent.contains("damaged"))
        #expect(
            try FileManager.default.contentsOfDirectory(
                atPath: url.deletingLastPathComponent().path(percentEncoded: false)
            ).contains { $0.contains("damaged") },
            "the file it could not read was thrown away"
        )
    }

    /// The file is the only copy of what was refused, so when it cannot be read it is never written over.
    @Test(.permissionsHold) func whatCannotBeReadIsKept() async throws {
        let directory = try TemporaryDirectory()
        let url = try directory.directory("Peel").appending(path: "refusals.json")
        try Data("[]".utf8).write(to: url)
        try directory.setPermissions(0, of: url)
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o644],
                ofItemAtPath: url.path(percentEncoded: false)
            )
        }

        let problem = await RefusalLog(url: url)
            .add([failure("/Users/me/a", .lastCopy)], source: "Editor", tool: "applications")
        let outcome = await RefusalLog(url: url).load()

        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path(percentEncoded: false))
        #expect(try Data(contentsOf: url) == Data("[]".utf8), "an unreadable record was written over")
        #expect(problem == .unreadable)
        #expect(outcome.problem == .unreadable && outcome.records == nil)
    }

    /// A refusal that could not be written down is said, rather than lost without a word.
    @Test(.permissionsHold) func saysWhenWhatWasRefusedCouldNotBeWritten() async throws {
        let directory = try TemporaryDirectory()
        let folder = try directory.directory("Peel")
        try directory.setPermissions(0o500, of: "Peel")
        defer { try? directory.setPermissions(0o700, of: "Peel") }

        let problem = await RefusalLog(url: folder.appending(path: "refusals.json"))
            .add([failure("/Users/me/a", .lastCopy)], source: "Editor", tool: "applications")

        #expect(problem == .couldNotRecord)
    }

    /// A record in a folder that cannot be searched may be there, so it is not called cleared.
    @Test func aRecordItCannotReachIsNotClearedAway() async throws {
        let directory = try TemporaryDirectory()
        let url = try directory.directory("Peel").appending(path: "refusals.json")
        try Data("[]".utf8).write(to: url)
        try directory.setPermissions(0o600, of: "Peel")
        defer { try? directory.setPermissions(0o755, of: "Peel") }

        #expect(await RefusalLog(url: url).clear(through: try trash(in: directory).service) == false)
    }

    @Test func clearMovesTheRecordToTheTrash() async throws {
        let directory = try TemporaryDirectory()
        let (service, folder) = try trash(in: directory)
        let log = RefusalLog(url: directory.url.appending(path: "Peel/refusals.json"))
        await log.add([failure("/Users/me/a", .lastCopy)], source: "Editor", tool: "applications")

        #expect(await log.clear(through: service))
        #expect(await log.load().records?.isEmpty == true)
        let trashed = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        #expect(trashed.count == 1)
        #expect(await RefusalLog(url: try #require(trashed.first)).load().records?.map(\.source) == ["Editor"])
        #expect(await log.clear(through: service), "forgetting what is already forgotten is no failure")
    }

    @Test func clearNeverMovesAFolderInThePlaceOfTheFile() async throws {
        let directory = try TemporaryDirectory()
        let (service, folder) = try trash(in: directory)
        let url = directory.url.appending(path: "Peel/refusals.json")
        try directory.file("Peel/refusals.json/kept.txt", contents: Data("work".utf8))

        #expect(await RefusalLog(url: url).clear(through: service) == false)
        #expect(FileManager.default.fileExists(atPath: url.appending(path: "kept.txt").path(percentEncoded: false)))
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false)).isEmpty)
    }

    private static let everyReason: [TrashFailure.Reason] = [
        .guarded(nil), .changedSinceScan, .claimedSinceScan, .lastCopy, .notPermitted, .needsHelper,
        .movedWithoutATrace, .somethingElseMoved(named: "x 2"), .historyUnreadable,
        .heldOpen(by: ["Figma Agent", "java"]), .peelRunsFromIt, .failed("x"),
    ] + GuardRefusal.allCases.map { .guarded($0) }

    /// A record stores its reason as a word, not a sentence, so a later version of Peel can still read it.
    @Test func everyReasonHasAWordOfItsOwn() {
        let reasons = Self.everyReason

        #expect(Set(reasons.map(\.name)).count == reasons.count)
        #expect(reasons.allSatisfy { !$0.name.contains(" ") })
        #expect(reasons.filter { $0.detail != nil }.count == 3)
    }

    /// History words a refusal from the reason it stored, so every word leads back to its reason, and a word a
    /// later version wrote is read as none rather than guessed at.
    @Test func everyReasonReadsBackFromItsWord() {
        for reason in Self.everyReason {
            #expect(TrashFailure.Reason(name: reason.name, detail: reason.detail) == reason)
        }
        #expect(TrashFailure.Reason(name: "a-word-from-later", detail: nil) == nil)
    }

    /// A refusal recorded before Peel kept the guard's reason reads as one whose reason is not known.
    @Test func anOldRefusalOfTheGuardStillReads() {
        #expect(TrashFailure.Reason(name: "protected-location", detail: nil) == .guarded(nil))
    }

    /// What one removal refused shares a batch and its source, so History shows it as one entry, in the words of
    /// the source Peel named.
    @Test func oneRemovalsRefusalsShareABatch() async throws {
        let directory = try TemporaryDirectory()
        let log = RefusalLog(url: directory.url.appending(path: "Peel/refusals.json"))

        await log.add([failure("/Users/me/a", .lastCopy), failure("/Users/me/b", .lastCopy)], source: "Duplicates", sourceKey: "tool", tool: "duplicates")
        await log.add([failure("/Users/me/c", .notPermitted)], source: "Editor", tool: "applications")

        let records = try #require(await log.load().records)
        let first = records.filter { $0.source == "Duplicates" }
        #expect(first.count == 2)
        #expect(Set(first.map(\.batch)).count == 1)
        #expect(first.allSatisfy { $0.batch != nil && $0.sourceKey == "tool" })
        #expect(records.first { $0.source == "Editor" }?.batch != first.first?.batch)
        #expect(records.first { $0.source == "Editor" }?.sourceKey == nil)
    }

    /// What one removal of several tools' selections refused is one entry with a part for each tool, in the order
    /// they were refused.
    @Test func aRemovalFromSeveralToolsHasARefusalPartForEach() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let batch = UUID()
        let stored = """
            [{"id":"\(UUID())","batch":"\(batch)","url":"file:///Users/me/b","reason":"last-copy","date":"2026-09-20T10:00:02Z","source":"Duplicates","sourceKey":"tool","tool":"duplicates"},
             {"id":"\(UUID())","batch":"\(batch)","url":"file:///Users/me/a","reason":"not-permitted","date":"2026-09-20T10:00:00Z","source":"Xcode","tool":"developer"}]
            """
        let groups = RefusalRecord.grouped(try decoder.decode([RefusalRecord].self, from: Data(stored.utf8)))

        #expect(groups.count == 1)
        #expect(groups.first?.parts == [
            RemovalPart(source: "Xcode", sourceKey: nil, tool: "developer"),
            RemovalPart(source: "Duplicates", sourceKey: "tool", tool: "duplicates"),
        ])
    }

    /// The log keeps each refusal's time to the millisecond, so the parts of one removal, refused within a second,
    /// keep the order they moved in however often the log is written again. A log written to the second reads too.
    @Test func refusalsKeepTheOrderTheyWereRefusedInWithinASecond() async throws {
        let directory = try TemporaryDirectory()
        let url = directory.url.appending(path: "refusals.json")
        let batch = UUID()
        let stored = """
            [{"id":"\(UUID())","batch":"\(batch)","url":"file:///Users/me/a","reason":"claimed-since-scan","date":"2026-09-20T10:00:00.100Z","source":"com.gone.app","tool":"orphans"},
             {"id":"\(UUID())","batch":"\(batch)","url":"file:///Users/me/b","reason":"last-copy","date":"2026-09-20T10:00:00.300Z","source":"Duplicates","sourceKey":"tool","tool":"duplicates"},
             {"id":"\(UUID())","url":"file:///Users/me/old","reason":"not-permitted","date":"2026-09-19T10:00:00Z","source":"Editor","tool":"applications"}]
            """
        try Data(stored.utf8).write(to: url)

        await RefusalLog(url: url).add([failure("/Users/me/new", .notPermitted)], source: "Editor", tool: "applications")
        let records = try #require(await RefusalLog(url: url).load().records)

        #expect(records.count == 4)
        #expect(RefusalRecord.grouped(records).first { $0.id == batch }?.parts.map(\.tool) == ["orphans", "duplicates"])
        #expect(records.contains { $0.date == ISO8601DateFormatter().date(from: "2026-09-19T10:00:00Z") })
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

        #expect(groups.map { $0.parts.map(\.source) } == [["Duplicates"], ["Editor"]])
        #expect(groups.first?.id == batch)
        #expect(groups.first?.parts.first?.sourceKey == "tool")
        #expect(groups.first?.records.map(\.url.lastPathComponent) == ["a", "b"])
        #expect(groups.first?.date == ISO8601DateFormatter().date(from: "2026-09-20T10:00:00Z"))
        #expect(groups.last?.records.count == 1)
        #expect(groups.last?.parts == [RemovalPart(source: "Editor", sourceKey: nil, tool: "applications")])
    }
}
