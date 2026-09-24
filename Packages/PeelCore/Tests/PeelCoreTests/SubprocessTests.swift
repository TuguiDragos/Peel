import Foundation
@testable import PeelPrivileged
import Testing

/// A tool Peel runs must never hang Peel or crash it. Every run has a time limit, stops when its caller is
/// canceled, and returns a failure as a value, never as an exception.
struct SubprocessTests {
    @Test func readsBothStreamsAndTheStatus() async throws {
        let result = await Subprocess.run("/bin/sh", ["-c", "echo out; echo err >&2; exit 3"], timeout: 30)
        let output = try result.get()

        #expect(output.status == 3)
        #expect(output.text == "out\n")
        #expect(output.errorText == "err\n")
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

    @Test func aToolIsStoppedWhenWhoeverAskedGoesAway() async {
        let task = Task { await Subprocess.run("/bin/sleep", ["600"], timeout: 3_600) }
        // Long enough for the tool to start, even on a busy machine.
        try? await Task.sleep(for: .milliseconds(300))
        task.cancel()
        #expect(await task.value == .failure(.canceled))
    }

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

    /// A process the tool starts can outlive it and keep its pipe open. `run` returns without waiting for it.
    @Test func doesNotWaitForWhatTheToolLeftRunning() async throws {
        let started = ContinuousClock.now
        let output = try await Subprocess.run("/bin/sh", ["-c", "sleep 60 >&1 & echo done"], timeout: 30).get()

        #expect(output.text == "done\n")
        #expect(ContinuousClock.now - started < .seconds(30), "it waited for a child the tool left behind")
    }
}
