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

    func setPermissions(_ permissions: Int, of path: String) throws {
        try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.appending(path: path).path(percentEncoded: false))
    }
}
