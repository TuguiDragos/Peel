import Foundation
@testable import PeelCore
import Synchronization
import Testing

struct ConcurrentMapTests {
    @Test func keepsTheOrderAndRunsAFewAtATime() async {
        let running = Mutex((now: 0, most: 0))

        let results = await Array(0..<8).concurrentMap(width: 4) { number in
            running.withLock { $0.now += 1; $0.most = max($0.most, $0.now) }
            try? await Task.sleep(for: .milliseconds(500))
            running.withLock { $0.now -= 1 }
            return number * 10
        }

        #expect(results == [0, 10, 20, 30, 40, 50, 60, 70])
        #expect(running.withLock { $0.most } == 4)
    }

    @Test func startsNothingMoreOnceCanceled() async {
        let started = Mutex(0)
        let mapping = Task {
            await Array(0..<20).concurrentMap(width: 2) { _ in
                started.withLock { $0 += 1 }
                while !Task.isCancelled { await Task.yield() }
            }
        }
        while started.withLock({ $0 }) == 0 { await Task.yield() }
        mapping.cancel()
        _ = await mapping.value

        #expect(started.withLock { $0 } <= 2)
    }
}
