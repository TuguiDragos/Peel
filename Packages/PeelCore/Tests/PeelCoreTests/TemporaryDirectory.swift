import Foundation

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
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(count: bytes).write(to: fileURL)
        return fileURL
    }

    @discardableResult
    func file(_ path: String, contents: Data) throws -> URL {
        let fileURL = url.appending(path: path)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
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
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(String(repeating: "hello world ", count: 20_000).utf8).write(to: source)
        let ditto = try Process.run(URL(filePath: "/usr/bin/ditto"), arguments: ["--hfsCompression", source.path, fileURL.path])
        ditto.waitUntilExit()
        try FileManager.default.removeItem(at: source)
        var info = stat()
        guard lstat(fileURL.path(percentEncoded: false), &info) == 0, info.st_flags & UInt32(UF_COMPRESSED) != 0 else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: fileURL.path])
        }
        return fileURL
    }

    func setPermissions(_ permissions: Int, of path: String) throws {
        try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.appending(path: path).path(percentEncoded: false))
    }
}
