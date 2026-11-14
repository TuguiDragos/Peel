@testable import PeelCore
import Testing

@MainActor
struct OneRunAtATimeTests {
    @Test func runsOnceMoreForTheCallsMadeWhileItRan() async throws {
        let runs = OneRunAtATime()
        var count = 0
        var release: CheckedContinuation<Void, Never>?

        let first = Task {
            await runs.run {
                count += 1
                if count == 1 { await withCheckedContinuation { release = $0 } }
            }
        }
        while release == nil { try await Task.sleep(for: .milliseconds(1)) }
        await runs.run { count += 1 }
        await runs.run { count += 1 }
        #expect(count == 1)
        release?.resume()
        await first.value

        #expect(count == 2)
    }
}
