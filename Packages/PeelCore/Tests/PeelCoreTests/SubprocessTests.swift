import Foundation
@testable import PeelPrivileged
import Synchronization
import Testing

/// A tool Peel runs must never hang Peel or crash it. Every run stops when its caller is canceled, has a time limit
/// unless the person follows it and can stop it, and returns a failure as a value, never as an exception.
struct SubprocessTests {
    @Test func readsBothStreamsAndTheStatus() async throws {
        let result = await Subprocess.run("/bin/sh", ["-c", "echo out; echo err >&2; exit 3"], timeout: 30)
        let output = try result.get()

        #expect(output.status == 3)
        #expect(output.text == "out\n")
        #expect(output.errorText == "err\n")
    }

    @Test func aToolsErrorsCanBeReadInTheOrderItWroteThem() async throws {
        let script = "echo first; echo second >&2; echo third"
        let output = try await Subprocess.run("/bin/sh", ["-c", script], timeout: 30, errorsIntoOutput: true).get()

        #expect(output.text == "first\nsecond\nthird\n")
        #expect(output.standardError.isEmpty)
    }

    /// A pipe holds at most 64 KB. If one stream were read to its end before the other, a tool that fills the
    /// other would block and never end.
    @Test func aToolThatWritesALotToBothStreamsStillEnds() async throws {
        let script = "head -c 1000000 /dev/zero; head -c 1000000 /dev/zero >&2"
        let output = try await Subprocess.run("/bin/sh", ["-c", script], timeout: 60).get()

        #expect(output.status == 0)
        #expect(output.standardOutput.count == 1_000_000)
        #expect(output.standardError.count == 1_000_000)
    }

    /// Package Receipts runs a tool per package, several at a time, and macOS lets a process keep few files open.
    /// A run that kept its pipes would leave two for each of the hundred tools that end here.
    @Test func aRunLetsGoOfItsPipesWhenItEndsNotWhenItsTimeIsUp() async {
        let before = pipesOfToolsThatEnded()

        for _ in 0..<100 {
            _ = await Subprocess.run("/usr/bin/true", [], timeout: 600)
            _ = await Subprocess.run("/no/such/tool", [], timeout: 600)
        }

        #expect(pipesOfToolsThatEnded() - before < 100)
    }

    /// The pipes this process still reads whose other end has closed, as a tool's do once it ends. Counted rather
    /// than every open file, since the tests running beside this one open and close files of their own all along.
    private func pipesOfToolsThatEnded() -> Int {
        let size = proc_pidinfo(getpid(), PROC_PIDLISTFDS, 0, nil, 0)
        var descriptors = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(size) / MemoryLayout<proc_fdinfo>.size)
        let filled = proc_pidinfo(getpid(), PROC_PIDLISTFDS, 0, &descriptors, size)
        return descriptors.prefix(Int(max(filled, 0)) / MemoryLayout<proc_fdinfo>.size).count { descriptor in
            guard descriptor.proc_fdtype == PROX_FDTYPE_PIPE else { return false }
            var info = pipe_fdinfo()
            let expected = Int32(MemoryLayout<pipe_fdinfo>.size)
            return proc_pidfdinfo(getpid(), descriptor.proc_fd, PROC_PIDFDPIPEINFO, &info, expected) == expected
                && info.pipeinfo.pipe_peerhandle == 0
        }
    }

    @Test func aToolThatIsNotThereIsAFailureAndNotACrash() async {
        let result = await Subprocess.run("/no/such/tool", [], timeout: 5)
        guard case .failure(.couldNotStart) = result else {
            Issue.record("\(result)")
            return
        }
    }

    /// A tool can hang, like `launchctl bootout` for a job that ignores the signal, or `brew` waiting on a lock.
    /// The time limit keeps a removal from waiting on it forever.
    @Test func aToolThatNeverEndsIsStoppedWhenItsTimeIsUp() async {
        let result = await Subprocess.run("/bin/sleep", ["600"], timeout: 0.2)
        #expect(result == .failure(.timedOut))
    }

    /// The tool is sent `SIGTERM` first, then `SIGKILL` if it ignores it.
    @Test func aToolThatIgnoresBeingAskedToStopIsKilled() async {
        let result = await Subprocess.run("/bin/sh", ["-c", "trap '' TERM; while :; do :; done"], timeout: 0.2)
        #expect(result == .failure(.timedOut))
    }

    /// What a tool writes reaches whoever asked while the tool still runs, from either stream, so a long run can
    /// be followed as it goes.
    @Test func handsOverWhatTheToolWritesAsItWrites() async throws {
        let started = ContinuousClock.now
        let seen = Mutex<[(text: String, at: Duration)]>([])
        let output = try await Subprocess.run("/bin/sh", ["-c", "echo first; sleep 1; echo second >&2"], timeout: 30) { data in
            seen.withLock { $0.append((String(decoding: data, as: UTF8.self), ContinuousClock.now - started)) }
        }.get()

        let chunks = seen.withLock { $0 }
        let first = try #require(chunks.first { $0.text.contains("first") })
        let second = try #require(chunks.first { $0.text.contains("second") })
        #expect(second.at - first.at > .milliseconds(500), "the first line came only when the tool ended")
        #expect(output.text == "first\n" && output.errorText == "second\n")
    }

    /// A run without a time limit, which Homebrew's upgrades need, still stops when whoever asked goes away.
    @Test func aRunWithNoTimeLimitStopsWhenAsked() async throws {
        let task = try await sleeping(timeout: nil)
        task.cancel()
        #expect(await task.value == .failure(.canceled))
    }

    @Test func aToolIsStoppedWhenWhoeverAskedGoesAway() async throws {
        let task = try await sleeping(timeout: 3_600)
        task.cancel()
        #expect(await task.value == .failure(.canceled))
    }

    private func sleeping(
        timeout: TimeInterval?
    ) async throws -> Task<Result<Subprocess.Output, Subprocess.Failure>, Never> {
        let started = Mutex(false)
        let task = Task {
            await Subprocess.run("/bin/sh", ["-c", "echo started; exec /bin/sleep 600"], timeout: timeout) { _ in
                started.withLock { $0 = true }
            }
        }
        let clock = ContinuousClock()
        let start = clock.now
        while !started.withLock({ $0 }), clock.now - start < .seconds(10) {
            try await Task.sleep(for: .milliseconds(5))
        }
        guard started.withLock({ $0 }) else {
            task.cancel()
            throw Unstarted()
        }
        return task
    }

    private struct Unstarted: Error {}

    /// A task that was already canceled starts no tool at all: a scan stopped between two steps must not launch
    /// the next one only to kill it, which on a busy Mac takes longer than a Stop is allowed. Asked for a tool
    /// that is not there, such a task answers that it was canceled, since it never tried to start one.
    @Test func aCanceledTaskStartsNothing() async {
        let task = Task { () -> Result<Subprocess.Output, Subprocess.Failure> in
            withUnsafeCurrentTask { $0?.cancel() }
            return await Subprocess.run("/no/such/tool", [], timeout: 30)
        }

        #expect(await task.value == .failure(.canceled))
    }

    /// A process the tool starts can outlive it and keep its pipe open. `run` returns without waiting for it. A run
    /// that waited would last the child's 90 seconds, longer than the rest of the suite can hold this test back.
    @Test func doesNotWaitForWhatTheToolLeftRunning() async throws {
        let started = ContinuousClock.now
        let output = try await Subprocess.run("/bin/sh", ["-c", "sleep 90 >&1 & echo done"], timeout: 30).get()

        #expect(output.text == "done\n")
        let took = ContinuousClock.now - started
        #expect(took < .seconds(90), "it waited for a child the tool left behind, \(took) in all")
    }
}
