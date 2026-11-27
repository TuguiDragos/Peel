import Foundation
import Synchronization

/// Runs `hdiutil` and `diskutil` for the tests that make disk images, and throws what the tool said when it fails.
enum DiskImageTool {
    struct Failure: Error, CustomStringConvertible {
        let command: String
        let status: Int32
        let said: String

        var description: String { "\(command) ended with \(status): \(said)" }
    }

    /// Runs `hdiutil` with `arguments`, `input` on its standard input, and answers what it wrote on standard output.
    @discardableResult
    static func hdiutil(_ arguments: String..., input: Data = Data()) async throws -> Data {
        try await hdiutil(arguments, input: input)
    }

    @discardableResult
    static func hdiutil(_ arguments: [String], input: Data = Data()) async throws -> Data {
        try await onAThreadOfItsOwn("/usr/bin/hdiutil", arguments, input: input).output
    }

    @discardableResult
    static func diskutil(_ arguments: String...) async throws -> Data {
        try await onAThreadOfItsOwn("/usr/sbin/diskutil", arguments, input: Data()).output
    }

    /// Takes the disk at `place`, a mount point or a device, away with `diskutil eject`, which `hdiutil` itself names
    /// in place of its `detach` on macOS 27, where `detach` waits on the disk image driver with the volume still
    /// mounted. Without `force`, a disk in use stays and the failure says what objects. Answers what the tool said.
    @discardableResult
    static func eject(_ place: String, force: Bool = true) throws -> String {
        let said = try streams("/usr/sbin/diskutil", ["eject"] + (force ? ["force"] : []) + [place], input: Data())
        return String(decoding: said.output + said.errors, as: UTF8.self)
    }

    /// At most one tool per processor.
    private static let turns = Turns(ProcessInfo.processInfo.activeProcessorCount)

    /// Runs the tool on its own thread, so no test thread waits for it.
    private static func onAThreadOfItsOwn(
        _ tool: String, _ arguments: [String], input: Data
    ) async throws -> (output: Data, errors: Data) {
        await turns.take()
        defer { turns.give() }
        return try await withCheckedThrowingContinuation { continuation in
            Thread { continuation.resume(with: Result { try streams(tool, arguments, input: input) }) }.start()
        }
    }

    /// The tool's streams are files rather than pipes, so neither can fill while the other waits to be read.
    private static func streams(
        _ tool: String, _ arguments: [String], input: Data
    ) throws -> (output: Data, errors: Data) {
        let streams = try TemporaryDirectory()
        let given = try streams.file("input", contents: input)
        let output = try streams.file("output", contents: Data())
        let errors = try streams.file("errors", contents: Data())
        let process = Process()
        process.executableURL = URL(filePath: tool)
        process.arguments = arguments
        process.standardInput = try FileHandle(forReadingFrom: given)
        process.standardOutput = try FileHandle(forWritingTo: output)
        process.standardError = try FileHandle(forWritingTo: errors)
        try process.run()
        process.waitUntilExit()
        let answer = try Data(contentsOf: output)
        let complaints = try Data(contentsOf: errors)
        guard process.terminationStatus == 0 else {
            let said = String(decoding: answer + complaints, as: UTF8.self)
            throw Failure(
                command: ([tool] + arguments).joined(separator: " "), status: process.terminationStatus,
                said: said.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        return (answer, complaints)
    }

    /// A set number of turns, waited for without holding a thread.
    private final class Turns: Sendable {
        private struct State {
            var free: Int
            var waiting: [CheckedContinuation<Void, Never>] = []
        }

        private let state: Mutex<State>

        init(_ count: Int) {
            state = Mutex(State(free: count))
        }

        func take() async {
            await withCheckedContinuation { continuation in
                let isFree = state.withLock { state in
                    guard state.free > 0 else {
                        state.waiting.append(continuation)
                        return false
                    }
                    state.free -= 1
                    return true
                }
                if isFree { continuation.resume() }
            }
        }

        func give() {
            let next = state.withLock { state -> CheckedContinuation<Void, Never>? in
                guard !state.waiting.isEmpty else {
                    state.free += 1
                    return nil
                }
                return state.waiting.removeFirst()
            }
            next?.resume()
        }
    }
}
