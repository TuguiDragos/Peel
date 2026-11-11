import Foundation
@testable import PeelCore
import PeelPrivileged
import Synchronization
import Testing

/// A program the account can rewrite runs as its own responsible process, or it doesn't run at all.
struct OnItsOwnTests {
    private let environment = ["PATH": "/usr/bin:/bin"]

    @Test func readsBothStreamsAndTheStatus() async throws {
        let output = try await Subprocess.runOnItsOwn(
            "/bin/sh", ["-c", "echo out; echo err >&2; exit 3"], environment: environment, timeout: 30
        ).get()

        #expect(output.status == 3)
        #expect(output.text == "out\n")
        #expect(output.errorText == "err\n")
    }

    @Test func aProgramsErrorsCanBeReadInTheOrderItWroteThemAndFollowedAsTheyCome() async throws {
        let seen = Mutex("")
        let output = try await Subprocess.runOnItsOwn(
            "/bin/sh", ["-c", "echo first; echo second >&2; echo third"], environment: environment, timeout: nil,
            errorsIntoOutput: true
        ) { data in
            seen.withLock { $0 += String(decoding: data, as: UTF8.self) }
        }.get()

        #expect(output.text == "first\nsecond\nthird\n")
        #expect(output.standardError.isEmpty)
        #expect(seen.withLock { $0 } == output.text)
    }

    @Test func theProgramAnswersForItselfWhileOneStartedPlainlyAnswersToWhoeverStartedIt() throws {
        let system = try #require(Subprocess.Responsibility.system)
        let held = try Subprocess.Held.start("/bin/cat", [], environment: environment, asking: system).get()
        defer {
            kill(held.pid, SIGKILL)
            waitpid(held.pid, nil, 0)
            close(held.output)
            if let errors = held.errors { close(errors) }
        }
        let plain = Process()
        plain.executableURL = URL(filePath: "/bin/cat")
        plain.standardInput = Pipe()
        try plain.run()
        defer { plain.terminate() }

        #expect(system.responsible(held.pid) == held.pid)
        #expect(system.responsible(plain.processIdentifier) != plain.processIdentifier)
        var state = proc_bsdinfo()
        try #require(proc_pidinfo(held.pid, PROC_PIDTBSDINFO, 0, &state, Int32(MemoryLayout<proc_bsdinfo>.size)) > 0)
        #expect(state.pbi_status == SSTOP, "the program runs before macOS was asked who answers for it")
    }

    @Test func nothingRunsThatMacOSDidNotStartApartFromPeel() async throws {
        let system = try #require(Subprocess.Responsibility.system)
        let directory = try TemporaryDirectory()
        let unmarked = Subprocess.Responsibility(disclaim: { _ in 0 }, responsible: system.responsible)
        let refused = Subprocess.Responsibility(disclaim: { _ in EINVAL }, responsible: system.responsible)

        for (name, asking) in [("unmarked", unmarked), ("refused", refused), ("not offered", nil)] {
            let mark = directory.url.appending(path: name)
            let result = await Subprocess.runOnItsOwn(
                "/usr/bin/touch", [mark.path(percentEncoded: false)], environment: environment, timeout: 30,
                asking: asking
            )

            #expect(result == .failure(.couldNotStart(Subprocess.notOnItsOwn)), "\(name)")
            #expect(mark.isMissing, "\(name): the program ran")
        }
    }

    @Test func aProgramThatIsNotThereFailsAsAValue() async {
        let result = await Subprocess.runOnItsOwn("/no/such/tool", [], environment: environment, timeout: 30)

        guard case .failure(.couldNotStart) = result else {
            Issue.record("a missing program gave \(result)")
            return
        }
    }

    @Test func givesTheProgramOnlyTheEnvironmentItIsHanded() async throws {
        let handed = ["PATH": "/usr/bin:/bin", "PEEL_TEST_NAME": "a value with spaces"]

        let output = try await Subprocess.runOnItsOwn("/usr/bin/env", [], environment: handed, timeout: 30).get()

        #expect(output.text.split(separator: "\n").sorted() == ["PATH=/usr/bin:/bin", "PEEL_TEST_NAME=a value with spaces"])
    }

    @Test func handsDownNoOpenFileOfWhoeverStartsIt() async throws {
        let file = open("/dev/null", O_RDONLY)
        let kept = fcntl(file, F_DUPFD, 200)
        defer {
            close(file)
            close(kept)
        }
        try #require(kept >= 200)

        let output = try await Subprocess.runOnItsOwn(
            "/bin/sh", ["-c", "echo /dev/fd/*"], environment: environment, timeout: 30
        ).get()

        #expect(output.text.contains("/dev/fd/1"))
        #expect(!output.text.split(separator: " ").contains("/dev/fd/\(kept)"))
    }

    @Test func aProgramThatRunsPastItsTimeIsStoppedEvenWhenItIgnoresBeingAsked() async {
        let script = "trap '' TERM; while :; do sleep 1; done"

        let result = await Subprocess.runOnItsOwn("/bin/sh", ["-c", script], environment: environment, timeout: 0.2)

        #expect(result == .failure(.timedOut))
    }

    @Test func aProgramIsStoppedWhenWhoeverAskedGoesAway() async throws {
        let directory = try TemporaryDirectory()
        let mark = directory.url.appending(path: "started")
        let environment = environment
        let task = Task {
            await Subprocess.runOnItsOwn(
                "/bin/sh", ["-c", #"touch "$0"; exec /bin/sleep 600"#, mark.path(percentEncoded: false)],
                environment: environment, timeout: 3_600
            )
        }
        while mark.isMissing {
            try await Task.sleep(for: .milliseconds(20))
        }

        task.cancel()

        #expect(await task.value == .failure(.canceled))
    }

    @Test func aProgramThatStopsIsNotTakenForOneThatEnded() async throws {
        let directory = try TemporaryDirectory()
        let started = directory.url.appending(path: "started")
        let resumed = directory.url.appending(path: "resumed")
        let environment = environment
        let task = Task {
            await Subprocess.runOnItsOwn(
                "/bin/sh", ["-c", #"echo $$ > "$0"; kill -STOP $$; touch "$1"; exec /bin/sleep 600"#,
                            started.path(percentEncoded: false), resumed.path(percentEncoded: false)],
                environment: environment, timeout: 3_600
            )
        }
        var program: pid_t?
        while program == nil {
            try await Task.sleep(for: .milliseconds(20))
            program = (try? String(contentsOf: started, encoding: .utf8)).flatMap {
                pid_t($0.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        try await Task.sleep(for: .milliseconds(200))
        kill(try #require(program), SIGCONT)
        while resumed.isMissing {
            try await Task.sleep(for: .milliseconds(20))
        }

        task.cancel()

        #expect(await task.value == .failure(.canceled))
    }

    @Test func aCanceledTaskStartsNothing() async {
        let environment = environment
        let task = Task { () -> Result<Subprocess.Output, Subprocess.Failure> in
            withUnsafeCurrentTask { $0?.cancel() }
            return await Subprocess.runOnItsOwn("/no/such/tool", [], environment: environment, timeout: 30)
        }

        #expect(await task.value == .failure(.canceled))
    }
}
