import Foundation
import Synchronization
@testable import PeelCore
import Testing

/// Stand-in measures for folders that never answer until the task that asked is canceled. A folder a file
/// provider holds can keep `FileSize` waiting like this until its budget runs out. A scan stopped while it
/// waits on one must return at once and ask about nothing more, or Stop would leave it walking the disk.
final class Unanswered: Sendable {
    private let asked = Mutex(0)
    private let finished = Mutex(false)

    var count: Int { asked.withLock { $0 } }

    var measure: FileSize.Measure {
        { [self] _ in
            await wait()
            return nil
        }
    }

    var walk: LeftoverScanner.Measure {
        { [self] _ in
            await wait()
            return nil
        }
    }

    var gather: FileSearch.Gather {
        { [self] _ in
            await wait()
            return nil
        }
    }

    private func wait() async {
        asked.withLock { $0 += 1 }
        try? await Task.sleep(for: .seconds(3_600))
    }

    /// Runs `scan` and cancels it 50 ms after its first request, once everything it asks at the same time is
    /// waiting. Returns how long the scan took to return after the cancel, and how many folders it asked about
    /// before and after it.
    func stop(_ scan: @escaping @Sendable () async -> Void) async throws -> (took: Duration, askedBefore: Int, askedAfter: Int) {
        let running = Task { [self] in
            await scan()
            finished.withLock { $0 = true }
        }
        let clock = ContinuousClock()
        while count == 0 {
            guard !finished.withLock({ $0 }) else {
                Issue.record("the scan finished without asking about a folder")
                return (.zero, 0, 0)
            }
            try await Task.sleep(for: .milliseconds(2))
        }
        try await Task.sleep(for: .milliseconds(50))
        let before = count
        let stopped = clock.now
        running.cancel()
        await running.value
        return (clock.now - stopped, before, count - before)
    }
}
