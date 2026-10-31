@testable import PeelCore
import Testing

@MainActor
struct StandingWorkTests {
    /// Remove Peel pauses the work Peel keeps running, a folder watcher among it, so nothing writes Peel's files again
    /// while they go to the Trash, and resumes it when Peel stays where it was.
    @Test func pausesEveryPieceAndResumesThem() async {
        var started = 0
        var ended = 0
        let (changes, _) = AsyncStream<Void>.makeStream()
        let work = StandingWork(scans: RunningScans())
        work.start([{
            started += 1
            for await _ in changes {}
            ended += 1
        }])
        await settle { started == 1 }

        work.pause()
        await settle { ended == 1 }
        #expect(ended == 1, "a piece went on after the pause")

        work.resume()
        await settle { started == 2 }
        #expect(started == 2)
        work.start([{ started += 10 }])
        await settle { false }
        #expect(started == 2, "a second start ran the work again")
        work.pause()
    }

    @Test func aPauseStopsEveryPagesScanAndWhatItWasGivenToStop() async {
        let scans = RunningScans()
        let work = StandingWork(scans: scans)
        let run = ScanRun(among: scans)
        let finished = ScanRun(among: scans)
        var stopped = 0
        _ = await finished.run { true }
        let (never, _) = AsyncStream<Void>.makeStream()
        work.start([{}], stoppingWithIt: [{ stopped += 1 }])
        let scan = Task {
            await run.run {
                for await _ in never {}
                return true
            }
        }
        await settle { run.isRunning }

        work.pause()

        #expect(!run.isRunning)
        #expect(run.wasStopped)
        #expect(!finished.wasStopped)
        #expect(stopped == 1)
        #expect(await scan.value == nil)
    }

    @Test func aScanOfAnotherListKeepsRunningThroughAPause() async {
        let work = StandingWork(scans: RunningScans())
        let run = ScanRun(among: RunningScans())
        let (never, _) = AsyncStream<Void>.makeStream()
        let scan = Task {
            await run.run {
                for await _ in never {}
                return true
            }
        }
        await settle { run.isRunning }

        work.pause()

        #expect(run.isRunning)
        run.stop()
        _ = await scan.value
    }

    private func settle(until done: () -> Bool) async {
        for _ in 0..<1_000 where !done() {
            await Task.yield()
        }
    }
}
