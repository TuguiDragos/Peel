import Foundation
@testable import Peel
@testable import PeelCore
import Testing

@MainActor
struct BackgroundItemLibraryTests {
    private let job = BackgroundItem(
        label: "org.example.agent", kind: .agent, source: .app, plistURL: nil, program: nil, runsAtLoad: nil,
        keepsAlive: nil, ownerBundleIdentifier: "org.example.app", ownerName: "App",
        ownerURL: URL(filePath: "/Applications/App.app", directoryHint: .isDirectory), isOrphan: false,
        state: .notLoaded, isDisabled: true
    )

    private final class Reads {
        var count = 0
        var library: BackgroundItemLibrary?
        var wereShownAsAScan: [Bool] = []
    }

    @Test func readsTheListAgainWithoutShowingAScan() async {
        let reads = Reads()
        let job = job
        let library = BackgroundItemLibrary { _, _ in
            reads.count += 1
            reads.wereShownAsAScan.append(reads.library?.isScanning == true)
            return BackgroundItems.Scan(items: reads.count > 1 ? [job] : [])
        }
        reads.library = library

        await library.readAgain(installedApps: [])
        #expect(reads.count == 0, "nothing is read again before the list was read once")

        await library.refresh(installedApps: [])
        let scans = library.scans
        await library.readAgain(installedApps: [])

        #expect(library.items?.map(\.label) == [job.label])
        #expect(library.scans == scans + 1, "the item's page asks macOS again")
        #expect(reads.wereShownAsAScan == [true, false], "a read again is announced to nobody")
    }

    private final class HeldAction {
        var calls = 0
        private var waiting: CheckedContinuation<Void, Never>?
        let (started, starting) = AsyncStream<Void>.makeStream()

        func run() async {
            calls += 1
            guard calls == 1 else { return }
            starting.yield()
            await withCheckedContinuation { waiting = $0 }
        }

        func release() {
            waiting?.resume()
            waiting = nil
        }
    }

    @Test func aSecondActionOnAJobDoesNothingWhileTheFirstRuns() async {
        let held = HeldAction()
        let job = job
        let library = BackgroundItemLibrary(
            scan: { _, _ in BackgroundItems.Scan(items: [job]) },
            control: { _, _ in await held.run() }
        )

        let first = Task { await library.perform(.start, on: job) }
        for await _ in held.started { break }
        await library.perform(.stop, on: job)
        #expect(held.calls == 1)
        held.release()
        await first.value

        #expect(held.calls == 1)
        #expect(library.runningActionItemIDs.isEmpty)
    }

    @Test func theReadAfterAnActionIsNotShownAsAScan() async {
        let reads = Reads()
        let job = job
        let library = BackgroundItemLibrary(
            scan: { _, _ in
                reads.count += 1
                reads.wereShownAsAScan.append(reads.library?.isScanning == true)
                return BackgroundItems.Scan(items: [job])
            },
            control: { _, _ in }
        )
        reads.library = library

        await library.refresh(installedApps: [])
        await library.perform(.start, on: job)

        #expect(reads.wereShownAsAScan == [true, false])
        #expect(library.scans == 2)
    }

    /// A scan whose answers the test gives, call by call, and which holds the calls in `held` until it lets them go.
    private final class Script {
        var calls = 0
        var answers: [Int: [BackgroundItem]] = [:]
        var held: Set<Int> = []
        private var waiting: [CheckedContinuation<Void, Never>] = []
        let (started, starting) = AsyncStream<Int>.makeStream()

        func scan() async -> BackgroundItems.Scan {
            calls += 1
            let call = calls
            starting.yield(call)
            if held.contains(call) {
                await withCheckedContinuation { waiting.append($0) }
            }
            return BackgroundItems.Scan(items: answers[call] ?? [])
        }

        func release() {
            waiting.forEach { $0.resume() }
            waiting = []
        }
    }

    @Test func anEnabledJobThatLeftIsToldWhenAnotherReadOvertakesTheActionsOwn() async {
        let script = Script()
        script.answers = [1: [job]]
        script.held = [2]
        let library = BackgroundItemLibrary { _, _ in await script.scan() }
        var started = script.started.makeAsyncIterator()
        await library.refresh(installedApps: [])
        _ = await started.next(isolation: #isolation)

        library.noteEnabled(job)
        let actionsOwn = Task { await library.refresh(installedApps: []) }
        _ = await started.next(isolation: #isolation)
        await library.refresh(installedApps: [])
        script.release()
        await actionsOwn.value

        guard case .enabledUntilLoaded(let label, _)? = library.alerts.current else {
            Issue.record("the job left the list without a word")
            return
        }
        #expect(label == job.label)
    }

    @Test func aReadStartedBeforeTheEnableDoesNotJudgeIt() async {
        let script = Script()
        script.answers = [1: [job]]
        script.held = [2]
        let library = BackgroundItemLibrary { _, _ in await script.scan() }
        var started = script.started.makeAsyncIterator()
        await library.refresh(installedApps: [])
        _ = await started.next(isolation: #isolation)

        let earlier = Task { await library.refresh(installedApps: []) }
        _ = await started.next(isolation: #isolation)
        library.noteEnabled(job)
        script.release()
        await earlier.value
        let afterTheEarlierRead = library.alerts.current

        await library.refresh(installedApps: [])

        #expect(afterTheEarlierRead == nil, "a list read before the enable says nothing about it")
        #expect(library.alerts.current != nil)
    }

    @Test func anEnabledJobThatLeftTheListSaysWhenItComesBack() {
        let left = BackgroundItemLibrary.alertAfterEnabling(job, listed: [])
        guard case .enabledUntilLoaded(let label, let kind)? = left else {
            Issue.record("no alert for a job that left the list")
            return
        }
        #expect(label == "org.example.agent" && kind == .agent)
        #expect(BackgroundItemLibrary.alertAfterEnabling(job, listed: [job]) == nil)
    }

    private let agent = BackgroundItem(
        label: "org.example.agent", kind: .agent, source: .userLibrary,
        plistURL: URL(filePath: "/Users/x/Library/LaunchAgents/org.example.agent.plist"), program: "/bin/sleep",
        runsAtLoad: nil, keepsAlive: nil, ownerBundleIdentifier: nil, ownerName: nil, ownerURL: nil, isOrphan: false,
        state: .running(pid: 7), isDisabled: false
    )

    private func edited(_ agent: BackgroundItem) -> LaunchAgentFile {
        LaunchAgentFile(url: agent.plistURL!, label: agent.label, text: "", opened: FileIdentity(stat()), mode: 0o644)
    }

    private func movedFile(of agent: BackgroundItem) -> TrashResult {
        TrashResult(trashed: [
            TrashedItem(originalURL: agent.plistURL!, trashedURL: URL(filePath: "/Users/x/.Trash/a.plist"), date: .now),
        ])
    }

    @Test func anEditWritesDownWhatMovedThenReadsTheListAgain() async throws {
        let agent = agent
        let moved = movedFile(of: agent)
        let library = BackgroundItemLibrary(
            scan: { _, _ in BackgroundItems.Scan(items: [agent]) },
            edit: { _, _, _, _ in .saved(moved: moved, reload: nil) }
        )
        await library.refresh(installedApps: [])
        let scans = library.scans
        var recorded: [TrashResult] = []

        let outcome = await library.save("text", editing: edited(agent), of: agent) { recorded.append($0) }

        guard case .saved? = outcome else { Issue.record("\(String(describing: outcome))"); return }
        #expect(recorded.map { $0.trashed.map(\.originalURL) } == [[agent.plistURL!]])
        #expect(library.scans == scans + 1)
        #expect(library.alerts.current == nil)
        #expect(library.runningActionItemIDs.isEmpty)
    }

    @Test func anEditThatLandedOnlyInPartIsSaidInAnAlert() async throws {
        let agent = agent
        let moved = movedFile(of: agent)
        let full = SystemError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC))
        let outcomes: [LaunchAgentFile.Outcome] = [
            .saved(moved: moved, reload: .notStarted(.disabled)),
            .oldFileInTheTrash(.incomplete(full), moved: moved),
            .unchanged(.labelChanged, moved: TrashResult()),
        ]
        for outcome in outcomes {
            let library = BackgroundItemLibrary(
                scan: { _, _ in BackgroundItems.Scan(items: [agent]) },
                edit: { _, _, _, _ in outcome }
            )
            var recorded = 0
            _ = await library.save("text", editing: edited(agent), of: agent) { _ in recorded += 1 }

            switch (outcome, library.alerts.current) {
            case (.saved, .edited(let label, .notStarted(.disabled))?):
                #expect(label == agent.label && recorded == 1)
            case (.oldFileInTheTrash, .notEdited(let label, let url, .incomplete(full))?):
                #expect(label == agent.label && url == agent.plistURL && recorded == 1)
            case (.unchanged, nil):
                #expect(recorded == 0)
            default:
                Issue.record("\(outcome)")
            }
        }
    }

    @Test func anEditDoesNothingWhileAnotherActionOnTheJobRuns() async {
        let held = HeldAction()
        let agent = agent
        let edits = Reads()
        let library = BackgroundItemLibrary(
            scan: { _, _ in BackgroundItems.Scan(items: [agent]) },
            control: { _, _ in await held.run() },
            edit: { _, _, _, _ in
                edits.count += 1
                return .unchanged(.changed, moved: TrashResult())
            }
        )

        let first = Task { await library.perform(.stop, on: agent) }
        for await _ in held.started { break }
        let outcome = await library.save("text", editing: edited(agent), of: agent) { _ in }
        held.release()
        await first.value

        #expect(outcome == nil)
        #expect(edits.count == 0)
    }
}
