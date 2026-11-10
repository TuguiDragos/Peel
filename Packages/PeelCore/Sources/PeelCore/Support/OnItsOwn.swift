import Darwin
public import Foundation
public import PeelPrivileged
import Synchronization

extension Subprocess {
    /// The two calls macOS has for which process answers for another, as it judges access to what it protects. No
    /// header of the SDK declares them, so they are looked up as Peel runs and nothing is started without them.
    struct Responsibility: Sendable {
        /// Marks spawn attributes so that the program started with them answers for itself.
        let disclaim: @Sendable (UnsafeMutablePointer<posix_spawnattr_t?>) -> Int32
        let responsible: @Sendable (pid_t) -> pid_t

        static let system: Responsibility? = {
            typealias Disclaim = @convention(c) (UnsafeMutablePointer<posix_spawnattr_t?>, Int32) -> Int32
            typealias Responsible = @convention(c) (pid_t) -> pid_t
            let everyImage = UnsafeMutableRawPointer(bitPattern: -2)
            guard let disclaim = dlsym(everyImage, "responsibility_spawnattrs_setdisclaim"),
                  let responsible = dlsym(everyImage, "responsibility_get_pid_responsible_for_pid")
            else { return nil }
            let mark = unsafeBitCast(disclaim, to: Disclaim.self)
            let ask = unsafeBitCast(responsible, to: Responsible.self)
            return Responsibility(disclaim: { mark($0, 1) }, responsible: { ask($0) })
        }()
    }

    static let notOnItsOwn = "Peel didn’t run it, since macOS couldn’t keep it from using Peel’s permissions."

    /// Runs a program the account can rewrite, or one that runs the account's files as code, such as Homebrew or a
    /// login shell: macOS judges what a program may reach by the app that started it, and this one must not reach
    /// what was given to Peel. So it starts as its own responsible process, and runs only once macOS says it answers
    /// for itself. It gets no input, no open file of Peel's and only `environment`, and is stopped after `timeout`
    /// seconds, when there is one, or when the task is canceled. `errorsIntoOutput` and `onOutput` are `run`'s.
    @concurrent
    public static func runOnItsOwn(
        _ executable: String, _ arguments: [String], environment: [String: String], timeout: TimeInterval?,
        errorsIntoOutput: Bool = false, onOutput: (@Sendable (Data) -> Void)? = nil
    ) async -> Result<Output, Failure> {
        await runOnItsOwn(
            executable, arguments, environment: environment, timeout: timeout, errorsIntoOutput: errorsIntoOutput,
            onOutput: onOutput, asking: .system
        )
    }

    @concurrent
    static func runOnItsOwn(
        _ executable: String, _ arguments: [String], environment: [String: String], timeout: TimeInterval?,
        errorsIntoOutput: Bool = false, onOutput: (@Sendable (Data) -> Void)? = nil,
        asking responsibility: Responsibility?
    ) async -> Result<Output, Failure> {
        guard !Task.isCancelled else { return .failure(.canceled) }
        let held: Held
        switch Held.start(
            executable, arguments, environment: environment, errorsIntoOutput: errorsIntoOutput, asking: responsibility
        ) {
        case .success(let started): held = started
        case .failure(let failure): return .failure(failure)
        }
        let run = OwnRun(held.pid)
        let output = Reader(held.output, onRead: onOutput)
        let errors = held.errors.map { Reader($0, onRead: onOutput) }
        run.watch()
        kill(held.pid, SIGCONT)
        if let timeout {
            timers.asyncAfter(deadline: .now() + timeout) { [weak run] in
                run?.stop(because: .timedOut)
            }
        }
        await withTaskCancellationHandler {
            await run.wait()
        } onCancel: {
            run.stop(because: .canceled)
        }
        let standardOutput = await output.data(within: drain)
        let standardError = await errors?.data(within: drain) ?? Data()
        close(held.output)
        if let errors = held.errors { close(errors) }
        if let failure = run.failure { return .failure(failure) }
        return .success(Output(status: run.status, standardOutput: standardOutput, standardError: standardError))
    }

    /// A program started and not yet let run, with the ends of its output and its errors Peel reads: one end for
    /// both when its errors go into its output.
    struct Held {
        let pid: pid_t
        let output: Int32
        let errors: Int32?

        /// Starts `executable` stopped, as its own responsible process, and keeps it only when macOS says so.
        static func start(
            _ executable: String, _ arguments: [String], environment: [String: String],
            errorsIntoOutput: Bool = false, asking responsibility: Responsibility?
        ) -> Result<Held, Failure> {
            guard let responsibility else { return .failure(.couldNotStart(notOnItsOwn)) }
            var output: [Int32] = [-1, -1]
            var errors: [Int32] = [-1, -1]
            guard pipe(&output) == 0 else { return .failure(.couldNotStart(String(cString: strerror(errno)))) }
            guard errorsIntoOutput || pipe(&errors) == 0 else {
                let reason = String(cString: strerror(errno))
                output.forEach { close($0) }
                return .failure(.couldNotStart(reason))
            }
            var actions: posix_spawn_file_actions_t?
            posix_spawn_file_actions_init(&actions)
            defer { posix_spawn_file_actions_destroy(&actions) }
            posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
            posix_spawn_file_actions_adddup2(&actions, output[1], 1)
            posix_spawn_file_actions_adddup2(&actions, errorsIntoOutput ? output[1] : errors[1], 2)

            var attributes: posix_spawnattr_t?
            posix_spawnattr_init(&attributes)
            defer { posix_spawnattr_destroy(&attributes) }
            // Peel ignores signals while it moves files, and a program started then would inherit that.
            var every = sigset_t()
            var none = sigset_t()
            sigfillset(&every)
            sigemptyset(&none)
            posix_spawnattr_setsigdefault(&attributes, &every)
            posix_spawnattr_setsigmask(&attributes, &none)
            let flags = POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_START_SUSPENDED | POSIX_SPAWN_SETSIGDEF
                | POSIX_SPAWN_SETSIGMASK
            posix_spawnattr_setflags(&attributes, Int16(flags))
            let isMarked = responsibility.disclaim(&attributes) == 0

            var pid: pid_t = 0
            var failure: String?
            if isMarked {
                let argv = ([executable] + arguments).map { strdup($0) } + [nil]
                let envp = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
                defer { (argv + envp).forEach { free($0) } }
                let status = posix_spawn(&pid, executable, &actions, &attributes, argv, envp)
                if status != 0 { failure = String(cString: strerror(status)) }
            } else {
                failure = notOnItsOwn
            }
            close(output[1])
            if !errorsIntoOutput { close(errors[1]) }
            if failure == nil, responsibility.responsible(pid) != pid {
                kill(pid, SIGKILL)
                waitpid(pid, nil, 0)
                failure = notOnItsOwn
            }
            if let failure {
                close(output[0])
                if !errorsIntoOutput { close(errors[0]) }
                return .failure(.couldNotStart(failure))
            }
            return .success(Held(pid: pid, output: output[0], errors: errorsIntoOutput ? nil : errors[0]))
        }
    }

    /// One program running on its own: whoever waits for it is woken once, and it is stopped once, for one reason.
    private final class OwnRun: Sendable {
        private struct State {
            var hasEnded = false
            var status: Int32 = 0
            var failure: Failure?
            var waiter: CheckedContinuation<Void, Never>?
        }

        private let state = Mutex(State())
        private let pid: pid_t

        init(_ pid: pid_t) {
            self.pid = pid
        }

        var failure: Failure? { state.withLock { $0.failure } }
        /// The exit code, or the number of the signal that ended it, as `Process` reports one.
        var status: Int32 { state.withLock { $0.status & 0x7F == 0 ? ($0.status >> 8) & 0xFF : $0.status & 0x7F } }

        func wait() async {
            await withCheckedContinuation { continuation in
                let hasEnded = state.withLock { state in
                    if !state.hasEnded { state.waiter = continuation }
                    return state.hasEnded
                }
                if hasEnded { continuation.resume() }
            }
        }

        /// Waits for the program's end as the kernel reports one, which comes only for an end: macOS's `waitid`
        /// answers for a stopped program too, and this one starts stopped. Its end is noted before it is reaped:
        /// until then its number stands for nothing else, so a stop never signals another process.
        func watch() {
            let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: Subprocess.timers)
            source.setEventHandler { [self] in
                source.cancel()
                ended {
                    var status: Int32 = 0
                    while waitpid(pid, &status, 0) == -1, errno == EINTR {}
                    return status
                }
            }
            source.resume()
        }

        private func ended(reaping reap: () -> Int32 = { 0 }) {
            let waiter = state.withLock { state -> CheckedContinuation<Void, Never>? in
                guard !state.hasEnded else { return nil }
                state.hasEnded = true
                state.status = reap()
                defer { state.waiter = nil }
                return state.waiter
            }
            waiter?.resume()
        }

        func stop(because reason: Failure) {
            let isFirst = state.withLock { state in
                guard !state.hasEnded, state.failure == nil else { return false }
                state.failure = reason
                kill(pid, SIGTERM)
                return true
            }
            guard isFirst else { return }
            Subprocess.timers.asyncAfter(deadline: .now() + Subprocess.grace) { [self] in
                state.withLock { state in
                    if !state.hasEnded { kill(pid, SIGKILL) }
                }
                // A program stuck in the kernel survives even `SIGKILL`, so the waiter is let go anyway.
                Subprocess.timers.asyncAfter(deadline: .now() + Subprocess.grace) { [self] in
                    ended()
                }
            }
        }
    }
}
