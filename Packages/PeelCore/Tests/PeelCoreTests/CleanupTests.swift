import ArgumentParser
import Foundation
@testable import PeelCommandLine
@testable import PeelCore
import Synchronization
import Testing

/// Tests `Cleanup`, the one path every `peel` command that removes files goes through.
struct CleanupTests {
    private func service(
        in directory: borrowing TemporaryDirectory, exclusions: Exclusions = .none,
        onMove: @escaping @Sendable () -> Void = {}
    ) throws -> TrashService {
        let trash = try directory.directory("Trash")
        let environment = SearchEnvironment(
            homeDirectory: directory.url.appending(path: "home", directoryHint: .isDirectory),
            rootDirectory: directory.url.appending(path: "root", directoryHint: .isDirectory)
        )
        return TrashService(environment: environment, exclusions: exclusions) { url in
            onMove()
            let destination = trash.appending(path: UUID().uuidString)
            try FileManager.default.moveItem(at: url, to: destination)
            return destination
        }
    }

    private func cleanup(items: [(url: URL, size: Int64?)], service: TrashService) -> Cleanup {
        Cleanup.of(items, source: "Editor", tool: "developer", service: service)
    }

    /// The guard is asked before anything is printed, so what the plan says is what the move will do.
    @Test func asksTheGuardBeforeItPrintsThePlan() throws {
        let directory = try TemporaryDirectory()
        let cache = try directory.file("home/Library/Caches/com.example.editor/blob", bytes: 20)
        let documents = try directory.directory("home/Documents")
        let plan = cleanup(items: [(cache, 20), (documents, nil)], service: try service(in: directory))

        #expect(plan.moving.map(\.url) == [cache])
        #expect(plan.staying.map(\.url) == [documents])
        #expect(plan.staying.first?.refusal == .guarded(.staysItself))
        #expect(plan.total.known == 20)
    }

    /// While the saved exclusions can't be read nothing moves, and no item is blamed on a protected location or
    /// recorded as refused: the cause is the list, which the command names.
    @Test func movesNothingAndBlamesNoItemWhileTheExclusionsCannotBeRead() async throws {
        let directory = try TemporaryDirectory()
        let cache = try directory.file("home/Library/Caches/com.example.editor/blob", bytes: 20)
        let service = try service(in: directory, exclusions: .unreadable)
        let refusals = RefusalLog(url: directory.url.appending(path: "Peel/refusals.json"))
        let removals = RemovalLog(url: directory.url.appending(path: "Peel/removals.json"))
        let plan = cleanup(items: [(cache, 20)], service: service)

        #expect(plan.items.allSatisfy { $0.refusal == nil })
        await #expect(throws: AppLookup.Failure.self) {
            try await Output.$collected.withValue(Output.Collected()) {
                try await plan.run(
                    question: "?", dryRun: false, yes: true, using: service,
                    recordingIn: removals, refusals: refusals
                )
            }
        }
        #expect(FileManager.default.fileExists(atPath: cache.path(percentEncoded: false)))
        #expect(await refusals.load().records?.isEmpty == true)
    }

    /// While History cannot be read nothing moves, and the command says so above the list, with the way out.
    @Test(.permissionsHold) func saysSoWhenHistoryCannotBeRead() async throws {
        let directory = try TemporaryDirectory()
        let cache = try directory.file("home/Library/Caches/com.example.editor/blob", bytes: 20)
        let history = try directory.file("Peel/removals.json", contents: Data("[]".utf8))
        try directory.setPermissions(0, of: "Peel/removals.json")
        defer { try? directory.setPermissions(0o644, of: "Peel/removals.json") }
        let collected = Output.Collected()

        try await Output.$collected.withValue(collected) {
            try await cleanup(items: [(cache, 20)], service: try service(in: directory))
                .run(
                    question: "?",
                    dryRun: true,
                    yes: true,
                    using: try service(in: directory),
                    recordingIn: RemovalLog(url: history)
                )
        }

        #expect(collected.notes.hasPrefix("Peel couldn't read its History at \(history.path(percentEncoded: false)), so nothing will be moved."))
        #expect(collected.notes.contains("Start Over in History"))
    }

    /// The command line never uses the helper, so what needs administrator access stays and says so.
    @Test func leavesWhatNeedsAdministratorAccessForTheApp() throws {
        let directory = try TemporaryDirectory()
        let cache = try directory.file("home/Library/Caches/com.example.editor/blob", bytes: 20)
        let system = try directory.file("home/Library/Caches/com.example.other/blob", bytes: 30)
        let plan = Cleanup.of(
            [(cache, 20), (system, 30)],
            source: "Editor",
            tool: "developer",
            needingAdministrator: [system],
            service: try service(in: directory)
        )

        #expect(plan.moving.map(\.url) == [cache])
        #expect(plan.staying.first?.refusal == .needsHelper)
        #expect(plan.total.known == 20)
    }

    /// The moves are counted on the service the run moves through, and History goes to a folder of the test's
    /// own: a dry run that moved would otherwise go unnoticed, or write into the user's History.
    @Test func aDryRunMovesNothing() async throws {
        let directory = try TemporaryDirectory()
        let cache = try directory.file("home/Library/Caches/com.example.editor/blob", bytes: 20)
        let moves = Mutex(0)
        let service = try service(in: directory) { moves.withLock { $0 += 1 } }
        let plan = cleanup(items: [(cache, 20)], service: service)

        try await plan.run(
            question: "?", dryRun: true, yes: true, using: service,
            recordingIn: RemovalLog(url: directory.url.appending(path: "Peel/removals.json")),
            refusals: RefusalLog(url: directory.url.appending(path: "Peel/refusals.json"))
        )

        #expect(moves.withLock { $0 } == 0)
        #expect(FileManager.default.fileExists(atPath: cache.path(percentEncoded: false)))
    }

    /// What moved goes into the same History the app reads, as one batch that can be put back.
    @Test func movesAndRecordsWhatWasAskedFor() async throws {
        let directory = try TemporaryDirectory()
        let cache = try directory.file("home/Library/Caches/com.example.editor/blob", bytes: 20)
        let log = RemovalLog(url: directory.url.appending(path: "Peel/removals.json"))
        let refusals = RefusalLog(url: directory.url.appending(path: "Peel/refusals.json"))
        let service = try service(in: directory)
        let plan = cleanup(items: [(cache, 20)], service: service)

        try await plan.run(question: "?", dryRun: false, yes: true, using: service, recordingIn: log, refusals: refusals)

        let records = try #require(await RemovalLog(url: log.url).load().records)
        #expect(!FileManager.default.fileExists(atPath: cache.path(percentEncoded: false)))
        #expect(records.map(\.originalURL) == [cache])
        #expect(records.allSatisfy { $0.source == "Editor" && $0.tool == "developer" && $0.size == 20 })
        #expect(await RefusalLog(url: refusals.url).load().records?.isEmpty == true)
    }

    /// A removal that could not finish exits 1, and every item that stayed is recorded as refused.
    @Test func aRemovalThatCouldNotFinishExitsOneAndIsRecorded() async throws {
        let directory = try TemporaryDirectory()
        let cache = try directory.file("home/Library/Caches/com.example.editor/blob", bytes: 20)
        let log = RemovalLog(url: directory.url.appending(path: "Peel/removals.json"))
        let refusals = RefusalLog(url: directory.url.appending(path: "Peel/refusals.json"))
        let service = try service(in: directory)
        let plan = cleanup(items: [(cache, 20)], service: service)

        await #expect(throws: ExitCode.failure) {
            try await plan.run(
                question: "?",
                dryRun: false,
                yes: true,
                using: service,
                recordingIn: log,
                refusals: refusals
            ) { _, urls in
                TrashResult(failures: urls.map { TrashFailure(url: $0, reason: .changedSinceScan) })
            }
        }

        #expect(await RemovalLog(url: log.url).load().records?.isEmpty == true)
        #expect(await RefusalLog(url: refusals.url).load().records?.map(\.reason) == ["changed-since-scan"])
        #expect(FileManager.default.fileExists(atPath: cache.path(percentEncoded: false)))
    }

    /// A plan where everything stays exits 1, as `peel uninstall` does when its app stays, and as the tool's help
    /// says of anything that stayed where it was. Its refusals are still recorded, since a removal where everything
    /// stayed is exactly what the refusal log is for.
    @Test func whenEverythingStaysTheRemovalFailsAndIsWrittenDown() async throws {
        let directory = try TemporaryDirectory()
        let documents = try directory.directory("home/Documents")
        let log = RemovalLog(url: directory.url.appending(path: "Peel/removals.json"))
        let refusals = RefusalLog(url: directory.url.appending(path: "Peel/refusals.json"))
        let plan = cleanup(items: [(documents, nil)], service: try service(in: directory))

        await #expect(throws: ExitCode.failure) {
            try await plan.run(
                question: "?", dryRun: false, yes: true, using: try service(in: directory),
                recordingIn: log, refusals: refusals
            )
        }

        #expect(await RemovalLog(url: log.url).load().records?.isEmpty == true)
        #expect(await RefusalLog(url: refusals.url).load().records?.map(\.reason) == ["stays-in-place"])
        #expect(FileManager.default.fileExists(atPath: documents.path(percentEncoded: false)))
    }

    /// What moved is only in the Trash when History cannot be written, so the removal ends as one that failed.
    @Test func aRemovalHistoryCannotRecordFails() async throws {
        let directory = try TemporaryDirectory()
        let cache = try directory.file("home/Library/Caches/com.example.editor/blob", bytes: 20)
        try directory.file("Peel", bytes: 1)
        let log = RemovalLog(url: directory.url.appending(path: "Peel/removals.json"))
        let service = try service(in: directory)
        let plan = cleanup(items: [(cache, 20)], service: service)

        await #expect(throws: ExitCode.failure) {
            try await plan.run(question: "?", dryRun: false, yes: true, using: service, recordingIn: log)
        }
        #expect(!FileManager.default.fileExists(atPath: cache.path(percentEncoded: false)))
    }

    /// A dry run changes nothing, not even the refusal log.
    @Test func aDryRunWritesNothingDownEither() async throws {
        let directory = try TemporaryDirectory()
        let documents = try directory.directory("home/Documents")
        let refusals = RefusalLog(url: directory.url.appending(path: "Peel/refusals.json"))
        let plan = cleanup(items: [(documents, nil)], service: try service(in: directory))

        try await plan.run(question: "?", dryRun: true, yes: true, using: try service(in: directory), refusals: refusals)

        #expect(await RefusalLog(url: refusals.url).load().records?.isEmpty == true)
    }

    /// A refusal known before the move is shown in the plan, and is still recorded when the other items move.
    /// The app records such refusals too, so the refusal log means the same thing whether the app or `peel`
    /// wrote it.
    @Test func whatTheGuardRefusedIsJournalledBesideWhatMoved() async throws {
        let directory = try TemporaryDirectory()
        let cache = try directory.file("home/Library/Caches/com.example.editor/blob", bytes: 20)
        let documents = try directory.directory("home/Documents")
        let log = RemovalLog(url: directory.url.appending(path: "Peel/removals.json"))
        let refusals = RefusalLog(url: directory.url.appending(path: "Peel/refusals.json"))
        let service = try service(in: directory)
        let plan = cleanup(items: [(cache, 20), (documents, nil)], service: service)

        try await plan.run(question: "?", dryRun: false, yes: true, using: service, recordingIn: log, refusals: refusals)

        #expect(await RemovalLog(url: log.url).load().records?.map(\.originalURL) == [cache])
        #expect(await RefusalLog(url: refusals.url).load().records?.map(\.url) == [documents])
    }

    /// `peel uninstall` writes down what the guard refused before the move beside what moved, as every other
    /// command does, and an app the guard keeps where it is is written down too, though nothing moved.
    @Test func anUninstallWritesDownWhatTheGuardRefusedBeforeTheMove() async throws {
        let directory = try TemporaryDirectory()
        let app = try directory.directory("home/Applications/Editor.app")
        let cache = try directory.file("home/Library/Caches/com.example.editor/blob", bytes: 20)
        let documents = try directory.directory("home/Documents")
        let log = RemovalLog(url: directory.url.appending(path: "Peel/removals.json"))
        let refusals = RefusalLog(url: directory.url.appending(path: "Peel/refusals.json"))
        let service = try service(in: directory)
        let plan = UninstallPlan(app: app, items: [
            UninstallPlan.Item(url: app, size: 4_096, refusal: nil),
            UninstallPlan.Item(url: cache, size: 20, refusal: nil),
            UninstallPlan.Item(url: documents, size: nil, refusal: service.refusal(of: documents)),
        ], needsAdministrator: 0, needsReview: 0)

        #expect(await plan.record(await plan.move(using: service), from: "Editor", in: log, refusals: refusals))

        let moved = await RemovalLog(url: log.url).load().records?.map(\.originalURL.lastPathComponent)
        #expect(Set(moved ?? []) == ["Editor.app", "blob"])
        #expect(await RefusalLog(url: refusals.url).load().records?.map(\.url) == [documents])

        let kept = UninstallPlan(app: documents, items: [
            UninstallPlan.Item(url: documents, size: nil, refusal: service.refusal(of: documents)),
        ], needsAdministrator: 0, needsReview: 0)
        #expect(await kept.record(TrashResult(), from: "Documents", in: log, refusals: refusals))
        #expect(await RefusalLog(url: refusals.url).load().records?.map(\.url) == [documents, documents])
    }
}
