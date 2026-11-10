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
        try run("/usr/bin/hdiutil", arguments, input: input)
    }

    @discardableResult
    static func diskutil(_ arguments: String...) throws -> Data {
        try run("/usr/sbin/diskutil", arguments, input: Data())
    }

    /// The tool's streams are files rather than pipes, so neither can fill while the other waits to be read.
    private static func run(_ tool: String, _ arguments: [String], input: Data) throws -> Data {
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
        guard process.terminationStatus == 0 else {
            let said = String(decoding: answer + (try Data(contentsOf: errors)), as: UTF8.self)
            throw Failure(
                command: ([tool] + arguments).joined(separator: " "), status: process.terminationStatus,
                said: said.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        return answer
    }
}
