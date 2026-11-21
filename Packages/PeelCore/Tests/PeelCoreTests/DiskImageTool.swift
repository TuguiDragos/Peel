import Foundation

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
    static func hdiutil(_ arguments: String..., input: Data = Data()) throws -> Data {
        try hdiutil(arguments, input: input)
    }

    @discardableResult
    static func hdiutil(_ arguments: [String], input: Data = Data()) throws -> Data {
        try run("/usr/bin/hdiutil", arguments, input: input)
    }

    @discardableResult
    static func diskutil(_ arguments: String...) throws -> Data {
        try run("/usr/sbin/diskutil", arguments, input: Data())
    }

    /// Takes the disk at `place`, a mount point or a device, away with `diskutil eject`, which `hdiutil` itself names
    /// in place of its `detach` on macOS 27, where `detach` waits on the disk image driver with the volume still
    /// mounted. Without `force`, a disk in use stays and the failure says what objects. Answers what the tool said.
    @discardableResult
    static func eject(_ place: String, force: Bool = true) throws -> String {
        let said = try streams("/usr/sbin/diskutil", ["eject"] + (force ? ["force"] : []) + [place], input: Data())
        return String(decoding: said.output + said.errors, as: UTF8.self)
    }

    private static func run(_ tool: String, _ arguments: [String], input: Data) throws -> Data {
        try streams(tool, arguments, input: input).output
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
}
