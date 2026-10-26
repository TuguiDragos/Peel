@testable import PeelCore
import Synchronization
import Testing

@MainActor
struct ScanRunTests {
    /// Work that runs until it is stopped and records whether it was. It gives up after five seconds, so a test
    /// where nothing stops it fails instead of hanging.
    private final class Waiting: Sendable {
        private let state = Mutex((started: false, stopped: false))

        var started: Bool { state.withLock { $0.started } }
        var stopped: Bool { state.withLock { $0.stopped } }

        func run(answering answer: Int) async -> Int {
            state.withLock { $0.started = true }
            try? await Task.sleep(for: .seconds(5))
            state.withLock { $0.stopped = Task.isCancelled }
            return answer
        }

        func untilStarted() async {
            while !started {
                try? await Task.sleep(for: .milliseconds(1))
            }
        }
    }

    /// Work that waits, whatever cancels it, until the test lets it go, as a read waits while macOS asks.
    private final class Stuck: Sendable {
        private let state = Mutex<(started: Bool, waiter: CheckedContinuation<Void, Never>?)>((false, nil))

        func run() async -> Int {
            await withCheckedContinuation { waiter in state.withLock { $0 = (true, waiter) } }
            return 1
        }

        func release() {
            state.withLock {
                $0.waiter?.resume()
                $0.waiter = nil
            }
        }

        func untilStarted() async {
            while !state.withLock({ $0.started }) {
                try? await Task.sleep(for: .milliseconds(1))
            }
        }
    }

    @Test func aStoppedScanAnswersNothingAndSaysSo() async {
        let scan = ScanRun()
        let waiting = Waiting()
        let asking = Task { await scan.run { await waiting.run(answering: 1) } }
        await waiting.untilStarted()
        #expect(scan.isRunning)

        scan.stop()

        #expect(!scan.isRunning, "the page gives the Rescan button back at once")
        #expect(scan.wasStopped)
        #expect(await asking.value == nil)
        #expect(waiting.stopped, "stopping the scan stops the work, not only the wait for it")
    }

    /// A scan started while another runs stops the older one, whose answer nobody needs anymore.
    @Test func aNewerScanStopsTheOlderOne() async {
        let scan = ScanRun()
        let older = Waiting()
        let asking = Task { await scan.run { await older.run(answering: 1) } }
        await older.untilStarted()

        let newer = await scan.run { 2 }

        #expect(newer == 2)
        #expect(await asking.value == nil)
        #expect(older.stopped)
        #expect(!scan.isRunning)
        #expect(!scan.wasStopped, "overtaken is not stopped: the page has an answer")
    }

    /// A page that goes away takes its scan with it, which is not the same as the user stopping it.
    @Test func aCallerThatGoesAwayStopsItsScan() async {
        let scan = ScanRun()
        let waiting = Waiting()
        let asking = Task { await scan.run { await waiting.run(answering: 1) } }
        await waiting.untilStarted()

        asking.cancel()

        #expect(await asking.value == nil)
        #expect(waiting.stopped)
        #expect(!scan.isRunning)
        #expect(!scan.wasStopped)
    }

    @Test func aScanItsPageLeftIsNoLongerWaitedFor() async {
        let scan = ScanRun()
        let stuck = Stuck()
        let asking = Task { await scan.run { await stuck.run() } }
        await stuck.untilStarted()
        let wasWaitedFor = scan.isWaitedFor

        asking.cancel()
        await Task.yield()
        let isWaitedFor = scan.isWaitedFor
        let next = await scan.run { 2 }
        stuck.release()

        #expect(wasWaitedFor && !isWaitedFor)
        #expect(next == 2)
        #expect(await asking.value == nil)
        #expect(!scan.isRunning && !scan.wasStopped && !scan.isAbandoned)
    }

    /// While a scan runs, the page shows how many items it has read, a number that moves even while a folder
    /// does not answer.
    @Test func aScanSaysHowMuchItHasRead() async {
        let scan = ScanRun()
        let waiting = Waiting()
        let asking = Task {
            await scan.run {
                ScanCount.current?.add(42)
                return await waiting.run(answering: 1)
            }
        }
        await waiting.untilStarted()

        for _ in 0..<500 where scan.itemsRead != 42 {
            try? await Task.sleep(for: .milliseconds(10))
        }

        #expect(scan.itemsRead == 42)
        scan.stop()
        _ = await asking.value
    }

    @Test func aQuietReadShowsNothing() async {
        let scan = ScanRun()

        let wasRunning = await scan.runQuietly { scan.isRunning }

        #expect(wasRunning == false, "nothing turns busy, so the page announces nothing and keeps its Rescan button")
        #expect(!scan.isRunning && !scan.wasStopped)
    }

    @Test func aQuietReadNeverRunsOverAScan() async {
        let scan = ScanRun()
        let waiting = Waiting()
        let asking = Task { await scan.run { await waiting.run(answering: 1) } }
        await waiting.untilStarted()
        let quiet = Waiting()

        let answer = await scan.runQuietly { await quiet.run(answering: 2) }

        #expect(answer == nil)
        #expect(!quiet.started)
        #expect(scan.isRunning && !waiting.stopped, "the scan goes on")
        scan.stop()
        _ = await asking.value
    }

    @Test func aScanOvertakesAQuietRead() async {
        let scan = ScanRun()
        let quiet = Waiting()
        let asking = Task { await scan.runQuietly { await quiet.run(answering: 1) } }
        await quiet.untilStarted()

        #expect(await scan.run { 2 } == 2)
        #expect(await asking.value == nil)
        #expect(quiet.stopped)
        #expect(!scan.isRunning && !scan.wasStopped)
    }

    @Test func aScanAfterAStopIsNoLongerStopped() async {
        let scan = ScanRun()
        let waiting = Waiting()
        let asking = Task { await scan.run { await waiting.run(answering: 1) } }
        await waiting.untilStarted()
        scan.stop()
        _ = await asking.value

        #expect(await scan.run { 3 } == 3)
        #expect(!scan.wasStopped)
    }
}
