import Foundation
import os
@testable import PeelCore
import Testing

struct ProcessEndsTests {
    /// What `ends` yields until it finishes, or nil when it has not finished within `seconds`.
    private func collect(_ ends: AsyncStream<pid_t>, within seconds: Double = 10) async -> [pid_t]? {
        await withTaskGroup(of: [pid_t]?.self) { group in
            group.addTask {
                var seen: [pid_t] = []
                for await identifier in ends { seen.append(identifier) }
                return seen
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(seconds))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    @Test func tellsWhenARunningProgramEnds() async throws {
        let directory = try TemporaryDirectory()
        let program = try directory.runningProgram("Example.app/Contents/MacOS/example")

        let ends = ProcessEnds.of([program.processIdentifier])
        program.terminate()

        #expect(await collect(ends) == [program.processIdentifier])
    }

    @Test func tellsAtOnceOfAProgramThatHasEndedAlready() async throws {
        let directory = try TemporaryDirectory()
        let program = try directory.runningProgram("Example.app/Contents/MacOS/example")
        program.terminate()
        program.waitUntilExit()

        #expect(await collect(ProcessEnds.of([program.processIdentifier])) == [program.processIdentifier])
    }

    @Test func finishesOnlyOnceEveryProgramHasEnded() async throws {
        let directory = try TemporaryDirectory()
        let first = try directory.runningProgram("One.app/Contents/MacOS/one")
        let second = try directory.runningProgram("Two.app/Contents/MacOS/two")
        let finished = OSAllocatedUnfairLock(initialState: false)
        let ends = ProcessEnds.of([first.processIdentifier, second.processIdentifier, first.processIdentifier, -1])
        let collecting = Task {
            var seen: [pid_t] = []
            for await identifier in ends { seen.append(identifier) }
            finished.withLock { $0 = true }
            return seen
        }

        first.terminate()
        first.waitUntilExit()
        try await Task.sleep(for: .milliseconds(500))
        #expect(!finished.withLock { $0 })
        second.terminate()

        let seen = await withTaskGroup(of: [pid_t]?.self) { group in
            group.addTask { await collecting.value }
            group.addTask {
                try? await Task.sleep(for: .seconds(10))
                return nil
            }
            let answer = await group.next() ?? nil
            group.cancelAll()
            return answer
        }
        #expect(seen == [first.processIdentifier, second.processIdentifier])
    }

    @Test func finishesAtOnceWithNoProgramToWatch() async {
        #expect(await collect(ProcessEnds.of([0, -1]), within: 1) == [])
    }
}
