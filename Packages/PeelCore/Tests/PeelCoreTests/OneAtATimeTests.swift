@testable import PeelCore
import Testing

@MainActor
struct OneAtATimeTests {
    @Test func aRequestMadeWhileOneRunsWaitsAndOnlyTheLatestRuns() async {
        let line = OneAtATime<Bool>()
        var runs: [(value: Bool, anotherWaited: Bool)] = []
        var release: CheckedContinuation<Void, Never>?

        let first = Task {
            await line.ask(true) { value, anotherWaits in
                await withCheckedContinuation { release = $0 }
                runs.append((value, anotherWaits()))
            }
        }
        while release == nil { await Task.yield() }
        let second = Task { await line.ask(false) { value, anotherWaits in runs.append((value, anotherWaits())) } }
        let third = Task { await line.ask(true) { value, anotherWaits in runs.append((value, anotherWaits())) } }
        for _ in 0..<20 { await Task.yield() }
        release?.resume()
        await first.value
        await second.value
        await third.value

        #expect(runs.map(\.value) == [true, true])
        #expect(runs.map(\.anotherWaited) == [true, false])
    }

    @Test func aRequestAloneRunsAtOnce() async {
        let line = OneAtATime<Int>()
        var ran: [Int] = []

        await line.ask(3) { value, anotherWaits in
            ran.append(value)
            #expect(!anotherWaits())
        }

        #expect(ran == [3])
    }
}
