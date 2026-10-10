import Darwin
public import Foundation
import Synchronization

/// The one way Peel and its helper run a tool. Every run stops when its task is canceled, and has a time limit
/// unless the person follows it and can stop it themselves: a removal waits for `launchctl` and `defaults`, and a
/// tool that never answers must not hold it forever. The pipes are read with `read(2)`, because `FileHandle`'s
/// `readDataToEndOfFile` and `availableData` raise an exception on failure that Swift cannot catch
/// (`NSFileHandle.h`).
public enum Subprocess {
    public struct Output: Sendable, Hashable {
        public let status: Int32
        public let standardOutput: Data
        public let standardError: Data

        public var text: String { String(decoding: standardOutput, as: UTF8.self) }
        public var errorText: String { String(decoding: standardError, as: UTF8.self) }
    }

    public enum Failure: Error, Sendable, Hashable {
        case couldNotStart(String)
        case timedOut
        case canceled

        /// The failure as a sentence, for places that pass a tool's output on to the user.
        public var explanation: String {
            switch self {
            case .couldNotStart(let reason): reason
            case .timedOut: "The tool didn’t answer in time, so it was stopped."
            case .canceled: "Stopped before it finished."
            }
        }
    }

    /// How long a tool that was asked to stop is given before it is killed.
    static let grace: TimeInterval = 2
    /// How long to wait for the rest of the output once the tool has ended. A process the tool started can
    /// outlive it and hold a pipe open, and the answer does not wait for that.
    static let drain: TimeInterval = 0.5
    /// At utility quality these timers would wait behind any utility work queued before them.
    static let timers = DispatchQueue.global(qos: .userInitiated)

    /// Runs `executable` with `arguments`, and stops it after `timeout` seconds, when there is one, or when the task
    /// is canceled. When `environment` is given, it replaces Peel's own. Both streams are read while the tool runs,
    /// so a tool that fills one pipe never waits on a reader that is busy with the other, and `onOutput` is handed
    /// what either stream brings as it comes. With `errorsIntoOutput`, the tool writes its errors into its output's
    /// pipe, so the two read in the order it wrote them and `standardError` is empty.
    @concurrent
    public static func run(
        _ executable: String,
        _ arguments: [String],
        environment: [String: String]? = nil,
        timeout: TimeInterval?,
        errorsIntoOutput: Bool = false,
        onOutput: (@Sendable (Data) -> Void)? = nil
    ) async -> Result<Output, Failure> {
        // A task stopped before this step starts nothing: launching the tool only to kill it would hold the Stop
        // for as long as the kill takes.
        guard !Task.isCancelled else { return .failure(.canceled) }
        let process = Process()
        process.executableURL = URL(filePath: executable)
        process.arguments = arguments
        if let environment { process.environment = environment }
        process.standardInput = FileHandle.nullDevice
        let outputPipe = Pipe()
        let errorPipe = errorsIntoOutput ? nil : Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe ?? outputPipe

        let run = Run(process)
        // The handler holds the run, which holds the process that holds the handler (`NSTask.h`), so it is let go
        // once the run is over, and the pipes with it: a pipe's descriptor closes only with the pipe.
        process.terminationHandler = { _ in run.ended() }
        defer { process.terminationHandler = nil }
        do {
            try process.run()
        } catch {
            return .failure(.couldNotStart(error.localizedDescription))
        }
        let output = Reader(outputPipe.fileHandleForReading.fileDescriptor, onRead: onOutput)
        let errors = errorPipe.map { Reader($0.fileHandleForReading.fileDescriptor, onRead: onOutput) }
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
        // Both readers have stopped by now, so nothing reads the descriptors any more.
        try? outputPipe.fileHandleForReading.close()
        try? errorPipe?.fileHandleForReading.close()
        if let failure = run.failure { return .failure(failure) }
        return .success(
            Output(status: process.terminationStatus, standardOutput: standardOutput, standardError: standardError)
        )
    }

    /// One tool being run: whoever waits for it is woken once, and it is stopped once, for one reason.
    private final class Run: Sendable {
        private struct State {
            var hasEnded = false
            var failure: Failure?
            var waiter: CheckedContinuation<Void, Never>?
        }

        private let state = Mutex(State())
        private let process: Process

        init(_ process: Process) {
            self.process = process
        }

        var failure: Failure? { state.withLock { $0.failure } }

        func wait() async {
            await withCheckedContinuation { continuation in
                let hasEnded = state.withLock { state in
                    if !state.hasEnded { state.waiter = continuation }
                    return state.hasEnded
                }
                if hasEnded { continuation.resume() }
            }
        }

        func ended() {
            let waiter = state.withLock { state in
                state.hasEnded = true
                defer { state.waiter = nil }
                return state.waiter
            }
            waiter?.resume()
        }

        /// Asks the tool to stop, and kills it after `grace` if it is still running. Without the kill,
        /// `launchctl bootout` of a job that ignores the signal would outlast its time limit.
        func stop(because reason: Failure) {
            let isFirst = state.withLock { state in
                guard !state.hasEnded, state.failure == nil else { return false }
                state.failure = reason
                return true
            }
            guard isFirst else { return }
            process.terminate()
            Subprocess.timers.asyncAfter(deadline: .now() + Subprocess.grace) { [self] in
                guard !state.withLock({ $0.hasEnded }), process.isRunning else { return }
                kill(process.processIdentifier, SIGKILL)
                // A tool stuck in the kernel survives even `SIGKILL`, so the waiter is let go anyway.
                Subprocess.timers.asyncAfter(deadline: .now() + Subprocess.grace) { [self] in
                    ended()
                }
            }
        }
    }

    /// Reads one pipe on a thread of its own with `read(2)`, which reports an error where `FileHandle` raises.
    /// It never blocks for long: a pipe held open by something the tool left running is given up on.
    private final class Reader: Sendable {
        private struct State {
            var data = Data()
            var isDone = false
            var giveUpAt: ContinuousClock.Instant?
            var waiter: CheckedContinuation<Void, Never>?
        }

        private let state = Mutex(State())
        /// Handed each piece as it is read, on the reading thread.
        private let onRead: (@Sendable (Data) -> Void)?

        init(_ descriptor: Int32, onRead: (@Sendable (Data) -> Void)?) {
            self.onRead = onRead
            let thread = Thread { [self] in
                read(descriptor)
                let waiter = state.withLock { state in
                    state.isDone = true
                    defer { state.waiter = nil }
                    return state.waiter
                }
                waiter?.resume()
            }
            thread.stackSize = 256 * 1_024
            thread.start()
        }

        /// Everything read, once the pipe has closed or `limit` has passed since this was asked.
        func data(within limit: TimeInterval) async -> Data {
            await withCheckedContinuation { continuation in
                let isDone = state.withLock { state in
                    state.giveUpAt = .now + .seconds(limit)
                    if !state.isDone { state.waiter = continuation }
                    return state.isDone
                }
                if isDone { continuation.resume() }
            }
            return state.withLock { $0.data }
        }

        private func read(_ descriptor: Int32) {
            var buffer = [UInt8](repeating: 0, count: 65_536)
            while true {
                if let giveUpAt = state.withLock({ $0.giveUpAt }), ContinuousClock.now >= giveUpAt { return }
                var waiting = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
                let ready = poll(&waiting, 1, 50)
                guard ready >= 0 || errno == EINTR else { return }
                guard ready > 0 else { continue }
                let count = Darwin.read(descriptor, &buffer, buffer.count)
                if count > 0 {
                    state.withLock { $0.data.append(contentsOf: buffer[0..<count]) }
                    onRead?(Data(buffer[0..<count]))
                } else if count == 0 || errno != EINTR {
                    return
                }
            }
        }
    }
}
