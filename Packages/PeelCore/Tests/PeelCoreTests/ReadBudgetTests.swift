import Foundation
@testable import PeelCore
import Synchronization
import Testing

struct ReadBudgetTests {
    @Test func theBudgetStartsAgainWhileMacOSAsksAndEndsOnceItStopsAsking() async {
        let asked = Mutex(0)
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            ReadBudget.end(
                after: 0.01, while: { asked.withLock { $0 += 1; return $0 < 3 } }, isWaiting: { true }
            ) { done.resume() }
        }

        #expect(asked.withLock { $0 } == 3)
    }

    @Test func aReadMacOSHoldsWhileItAsksIsWaitedFor() async {
        let released = DispatchSemaphore(value: 0)
        let read = { @Sendable (_: @escaping @Sendable () -> Bool) -> String in
            released.wait()
            return "answered"
        }

        let answer = await SlowRead.answer(within: 0.01, while: {
            released.signal()
            return true
        }, read)

        #expect(answer == "answered")
    }
}
