import Foundation
@testable import PeelCore
import Testing

/// A made-up home whose `.zshrc` sources Peel's file, the way a person's does once they add Peel's line.
struct ZshHome {
    let home: URL
    let peelFile: URL

    init(thenRun lines: [String] = []) throws {
        home = FileManager.default.temporaryDirectory.appending(path: "ZshHome-\(UUID().uuidString)", directoryHint: .isDirectory)
        peelFile = ShellFile.url(in: home.appending(path: "Library/Application Support/Peel", directoryHint: .isDirectory))
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try ([ShellFile.line(sourcing: peelFile, home: home)] + lines).joined(separator: "\n").appending("\n")
            .write(to: home.appending(path: ".zshrc"), atomically: true, encoding: .utf8)
    }

    var environment: [String: String] {
        [
            "HOME": home.path, "ZDOTDIR": home.path, "TERM": "xterm-256color", "PATH": "/usr/bin:/bin",
            "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": "/dev/null",
        ]
    }

    /// What a new interactive zsh prints for `command`. It has to start and run without a single error.
    func output(of command: String) throws -> String {
        let process = Process()
        process.executableURL = URL(filePath: "/bin/zsh")
        process.arguments = ["-i", "-c", command]
        process.environment = environment
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        let said = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let complained = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        #expect(complained.isEmpty, "\(complained)")
        return said
    }

    func answers(_ check: String) throws -> Bool {
        try output(of: "if \(check); then print yes; else print no; fi") == "yes\n"
    }
}
