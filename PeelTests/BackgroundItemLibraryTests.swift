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
}
