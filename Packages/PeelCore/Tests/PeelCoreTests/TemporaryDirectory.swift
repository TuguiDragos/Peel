import Foundation
import Testing

struct TemporaryDirectory: ~Copyable {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory.appending(path: "PeelCoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    @discardableResult
    func file(_ path: String, bytes: Int = 16) throws -> URL {
        let fileURL = url.appending(path: path)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(count: bytes).write(to: fileURL)
        return fileURL
    }

    @discardableResult
    func file(_ path: String, contents: Data) throws -> URL {
        let fileURL = url.appending(path: path)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: fileURL)
        return fileURL
    }

    @discardableResult
    func directory(_ path: String) throws -> URL {
        let directoryURL = url.appending(path: path, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL
    }

    /// Writes 240 KB of text at `path`, compressed into its resource fork by `ditto`, as macOS compresses a file.
    @discardableResult
    func compressedTextFile(_ path: String) throws -> URL {
        let fileURL = url.appending(path: path)
        let source = fileURL.deletingLastPathComponent().appending(path: ".source-\(fileURL.lastPathComponent)")
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(String(repeating: "hello world ", count: 20_000).utf8).write(to: source)
        // A ditto that can clone does so on the same volume, and a clone is never compressed, so it is told not to.
        let noClone = Self.dittoKnowsNoClone ? ["--noclone"] : []
        let ditto = try Process.run(
            URL(filePath: "/usr/bin/ditto"),
            arguments: noClone + ["--hfsCompression", source.path, fileURL.path]
        )
        ditto.waitUntilExit()
        try FileManager.default.removeItem(at: source)
        var info = stat()
        guard lstat(fileURL.path(percentEncoded: false), &info) == 0, info.st_flags & UInt32(UF_COMPRESSED) != 0 else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: fileURL.path])
        }
        return fileURL
    }

    private static let dittoKnowsNoClone: Bool = {
        let output = Pipe()
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/ditto")
        process.arguments = ["-h"]
        process.standardOutput = output
        process.standardError = output
        guard (try? process.run()) != nil else { return false }
        let help = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: help, as: UTF8.self).contains("--noclone")
    }()

    /// macOS kills a copy of one of its own programs started from anywhere else (a launch constraint), so the copy of
    /// `sleep` is signed ad hoc first.
    func runningProgram(_ path: String) throws -> Process {
        let program = url.appending(path: path)
        try FileManager.default.createDirectory(
            at: program.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.copyItem(at: URL(filePath: "/bin/sleep"), to: program)
        let signing = try Process.run(
            URL(filePath: "/usr/bin/codesign"),
            arguments: ["--force", "--sign", "-", program.path(percentEncoded: false)]
        )
        signing.waitUntilExit()
        guard signing.terminationStatus == 0 else {
            throw CocoaError(.executableLoad, userInfo: [NSFilePathErrorKey: program.path])
        }
        return try Process.run(program, arguments: ["30"])
    }

    func setPermissions(_ permissions: Int, of path: String) throws {
        try setPermissions(permissions, of: url.appending(path: path))
    }

    func setPermissions(_ permissions: Int, of item: URL) throws {
        if geteuid() == 0, permissions & 0o600 != 0o600 {
            Issue.record("this test takes permissions away, which root ignores, so it needs .permissionsHold")
        }
        let path = item.path(percentEncoded: false)
        try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: path)
    }
}
