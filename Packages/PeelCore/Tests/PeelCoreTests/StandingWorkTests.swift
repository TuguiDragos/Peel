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
        let work = StandingWork()
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

    private func settle(until done: () -> Bool) async {
        for _ in 0..<1_000 where !done() {
            await Task.yield()
        }
    }
}
