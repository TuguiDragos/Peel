import Foundation
@testable import PeelCore
import Synchronization
import Testing

/// A folder a file provider owns can hold a read in the kernel for minutes, and no answer is not an empty folder.
struct SlowReadTests {
    /// The read returns only after the wait has been given up on, so a busy Mac makes the test slower, never
    /// wrong.
    @Test func givesUpOnAReadThatDoesNotComeBack() async {
        let release = DispatchSemaphore(value: 0)
        let answer = await SlowRead.answer(within: 0.05) { _ in
            release.wait()
            return ["late"]
        }
        release.signal()

        #expect(answer == nil)
    }

    /// A read that works in steps is told when nobody waits for it anymore, and stops. The loop's time limit
    /// only keeps a broken build from spinning forever, so a busy Mac makes the test slower, never wrong.
    @Test func tellsAReadThatNobodyWaitsForAnymore() async {
        let started = Mutex(false)
        let stopped = Mutex(false)
        let asking = Task {
            await SlowRead.answer(within: 3_600) { isGivenUp in
                started.withLock { $0 = true }
                let clock = ContinuousClock()
                let start = clock.now
                while !isGivenUp(), clock.now - start < .seconds(60) {
                    usleep(1_000)
                }
                stopped.withLock { $0 = isGivenUp() }
                return 0
            }
        }
        while !started.withLock({ $0 }) {
            try? await Task.sleep(for: .milliseconds(1))
        }
        asking.cancel()
        #expect(await asking.value == nil)

        let clock = ContinuousClock()
        let start = clock.now
        while !stopped.withLock({ $0 }), clock.now - start < .seconds(10) {
            try? await Task.sleep(for: .milliseconds(5))
        }
        #expect(stopped.withLock { $0 })
    }

    @Test func answersWhatTheReadFound() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("folder/one")
        try directory.file("folder/two")
        let file = try directory.file("plain.txt")

        let names = try #require(await SlowRead.names(in: directory.url.appending(path: "folder")))
        #expect(Set(names) == ["one", "two"])
        // Anything that is not a folder holds nothing, which is an answer.
        #expect(await SlowRead.names(in: file) == [])
        #expect(await SlowRead.names(in: directory.url.appending(path: "missing")) == [])
    }
}
