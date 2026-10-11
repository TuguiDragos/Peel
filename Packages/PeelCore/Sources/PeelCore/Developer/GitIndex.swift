import Darwin
import Foundation
import PeelPrivileged

/// What a Git repository tracks, read from its index as `gitformat-index(5)` describes it. Peel never runs Git inside
/// a project: a repository's own settings can name a program for Git to run.
struct GitIndex: Sendable {
    struct Repository: Sendable, Hashable {
        let top: URL
        let gitDirectory: URL
    }

    private struct Unreadable: Error {}

    /// Every folder that holds a tracked path, a tracked submodule's own folder among them: its names below the
    /// working tree's top, in lowercase.
    private var folders: Set<[String]> = []
    /// The folders a sparse checkout leaves out of the working tree, everything in each of them tracked.
    private var sparseFolders: [[String]] = []

    /// An index larger than this is not read, and what Git tracks there is not known.
    static let maximumSize = 256 * 1_024 * 1_024

    /// The repository whose working tree holds `folder`, found as Git finds it: in `folder` and each folder above,
    /// never past the disk `folder` is on. A `.git` folder counts when it has a `HEAD`, and a `.git` file always
    /// does, since Git stops there even when the folder it names can't be read.
    static func repository(containing folder: URL) -> Repository? {
        let names = PathComponents.of(PathPattern.canonical(folder).path(percentEncoded: false))
        var device: dev_t?
        for count in stride(from: names.count, through: 0, by: -1) {
            let path = "/" + names.prefix(count).joined(separator: "/")
            var info = stat()
            guard stat(path, &info) == 0, device.map({ $0 == info.st_dev }) ?? true else { return nil }
            device = info.st_dev
            let top = URL(filePath: path, directoryHint: .isDirectory)
            if let gitDirectory = gitDirectory(at: top.appending(path: ".git")) {
                return Repository(top: top, gitDirectory: gitDirectory)
            }
        }
        return nil
    }

    private static func gitDirectory(at dotGit: URL) -> URL? {
        var info = stat()
        guard stat(dotGit.path(percentEncoded: false), &info) == 0 else { return nil }
        switch info.st_mode & S_IFMT {
        case S_IFDIR:
            return isGitDirectory(dotGit) ? dotGit : nil
        case S_IFREG:
            guard let data = BoundedRead.data(at: dotGit, maximum: 4_096),
                  let text = String(data: data, encoding: .utf8), text.hasPrefix("gitdir: ")
            else { return dotGit }
            let named = String(text.dropFirst("gitdir: ".count)).trimmingCharacters(in: CharacterSet(charactersIn: "\r\n"))
            return named.hasPrefix("/")
                ? URL(filePath: named, directoryHint: .isDirectory)
                : dotGit.deletingLastPathComponent().appending(path: named, directoryHint: .isDirectory)
        default:
            return nil
        }
    }

    private static func isGitDirectory(_ url: URL) -> Bool {
        !url.appending(path: "HEAD").isMissing
    }

    /// What Git tracks in `repository`, or nil when that is not known: a file the index needs can't be read whole,
    /// or it uses a form this reader doesn't know, which `gitformat-index(5)` asks tools to leave alone.
    static func read(_ repository: Repository) -> GitIndex? {
        let git = repository.gitDirectory
        guard isGitDirectory(git) else { return nil }
        let file = git.appending(path: "index")
        if file.isMissing { return GitIndex() }
        guard let length = objectNameLength(in: git), let data = BoundedRead.data(at: file, maximum: maximumSize)
        else { return nil }
        var index = GitIndex()
        do {
            if let shared = try index.add(data, objectNameLength: length) {
                let sharedFile = git.appending(path: "sharedindex.\(shared)")
                guard let sharedData = BoundedRead.data(at: sharedFile, maximum: maximumSize),
                      try index.add(sharedData, objectNameLength: length) == nil
                else { return nil }
            }
        } catch {
            return nil
        }
        return index
    }

    /// 32 bytes in a SHA-256 repository (`extensions.objectFormat`), 20 in one that uses SHA-1.
    private static func objectNameLength(in gitDirectory: URL) -> Int? {
        let config = commonDirectory(of: gitDirectory).appending(path: "config")
        if config.isMissing { return 20 }
        guard let data = BoundedRead.data(at: config), let text = String(data: data, encoding: .utf8)
        else { return nil }
        switch ToolSettings.gitValue(of: "objectformat", inSection: "extensions", in: text)?.lowercased() {
        case nil, "sha1": return 20
        case "sha256": return 32
        default: return nil
        }
    }

    /// The repository's own Git folder, which a worktree's names in `commondir`.
    private static func commonDirectory(of gitDirectory: URL) -> URL {
        guard let data = BoundedRead.data(at: gitDirectory.appending(path: "commondir"), maximum: 4_096),
              let named = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !named.isEmpty
        else { return gitDirectory }
        return named.hasPrefix("/")
            ? URL(filePath: named, directoryHint: .isDirectory)
            : gitDirectory.appending(path: named, directoryHint: .isDirectory)
    }

    /// True when Git tracks something at or inside `folder`, or `folder` sits in a folder a sparse checkout leaves
    /// out. Names are compared without case, so a guess holds back more, never less.
    func tracksSomething(atOrInside folder: URL, of repository: Repository) -> Bool {
        let top = PathComponents.of(repository.top.path(percentEncoded: false))
        let names = PathComponents.of(PathPattern.canonical(folder).path(percentEncoded: false))
        guard names.starts(with: top) else { return false }
        let relative = names.dropFirst(top.count).map { $0.lowercased() }
        return folders.contains(relative) || sparseFolders.contains { relative.starts(with: $0) }
    }

    /// Adds the entries of one index file, and returns the name of the shared index a split index lays them over.
    private mutating func add(_ data: Data, objectNameLength: Int) throws -> String? {
        try data.withUnsafeBytes { bytes in try add(bytes, objectNameLength: objectNameLength) }
    }

    private mutating func add(_ bytes: UnsafeRawBufferPointer, objectNameLength: Int) throws -> String? {
        // The index ends with a checksum as long as an object name.
        let end = bytes.count - objectNameLength
        guard end >= 12, bytes.bigEndian32(at: 0) == 0x4449_5243 else { throw Unreadable() }
        let version = bytes.bigEndian32(at: 4)
        guard (2...4).contains(version) else { throw Unreadable() }

        var offset = 12
        var previous: [UInt8] = []
        var previousFolder: ArraySlice<UInt8> = []
        for _ in 0..<bytes.bigEndian32(at: 8) {
            let start = offset
            offset += 40 + objectNameLength + 2
            guard offset <= end else { throw Unreadable() }
            let mode = bytes.bigEndian32(at: start + 24)
            let flags = bytes.bigEndian16(at: offset - 2)
            if flags & 0x4000 != 0 {
                guard version >= 3 else { throw Unreadable() }
                offset += 2
            }
            let path: [UInt8]
            if version == 4 {
                // The name drops this many bytes from the end of the one before it, and adds what follows.
                let (dropped, used) = try Self.variableLengthNumber(in: bytes, at: offset, end: end)
                offset += used
                let nul = try Self.nul(in: bytes, from: offset, end: end)
                guard dropped <= previous.count else { throw Unreadable() }
                path = Array(previous.dropLast(dropped)) + bytes[offset..<nul]
                offset = nul + 1
            } else {
                let nul = try Self.nul(in: bytes, from: offset, end: end)
                path = Array(bytes[offset..<nul])
                // Padded with 1 to 8 NUL bytes to a multiple of eight.
                offset = start + (((nul - start) + 8) & ~7)
                guard offset <= end else { throw Unreadable() }
            }
            let length = Int(flags & 0x0FFF)
            guard length == 0x0FFF ? path.count >= 0x0FFF : path.count == length else { throw Unreadable() }
            previous = path

            let folder = path[..<(path.lastIndex(of: UInt8(ascii: "/")) ?? 0)]
            let kind = mode & 0o170000
            if kind == 0o040000 || kind == 0o160000 || folder != previousFolder {
                add(path: path, isTrackedWhole: kind == 0o040000 || kind == 0o160000, isSparse: kind == 0o040000)
                previousFolder = folder
            }
        }

        var shared: String?
        while offset < end {
            guard end - offset >= 8 else { throw Unreadable() }
            let signature = Array(bytes[offset..<offset + 4])
            let size = Int(bytes.bigEndian32(at: offset + 4))
            let body = offset + 8
            guard size <= end - body else { throw Unreadable() }
            if signature == Array("link".utf8) {
                guard size >= objectNameLength else { throw Unreadable() }
                let name = bytes[body..<body + objectNameLength]
                if name.contains(where: { $0 != 0 }) { shared = name.hexadecimal }
            } else if !(UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(signature[0]), signature != Array("sdir".utf8) {
                // An extension whose name starts in lowercase changes what the entries mean.
                throw Unreadable()
            }
            offset = body + size
        }
        return shared
    }

    private mutating func add(path: [UInt8], isTrackedWhole: Bool, isSparse: Bool) {
        guard !path.isEmpty else { return }
        let names = path.split(separator: UInt8(ascii: "/")).map { String(decoding: $0, as: UTF8.self).lowercased() }
        for count in stride(from: isTrackedWhole ? names.count : names.count - 1, to: 0, by: -1) {
            guard folders.insert(Array(names.prefix(count))).inserted else { break }
        }
        if isSparse { sparseFolders.append(names) }
    }

    /// The number Git's offset encoding writes (`gitformat-pack(5)`), and how many bytes it took.
    private static func variableLengthNumber(
        in bytes: UnsafeRawBufferPointer, at start: Int, end: Int
    ) throws -> (value: Int, length: Int) {
        var offset = start
        guard offset < end else { throw Unreadable() }
        var byte = bytes[offset]
        offset += 1
        var value = Int(byte & 0x7F)
        while byte & 0x80 != 0 {
            guard offset < end, value < Int.max >> 8 else { throw Unreadable() }
            byte = bytes[offset]
            offset += 1
            value = ((value + 1) << 7) | Int(byte & 0x7F)
        }
        return (value, offset - start)
    }

    private static func nul(in bytes: UnsafeRawBufferPointer, from start: Int, end: Int) throws -> Int {
        guard let nul = bytes[start..<end].firstIndex(of: 0) else { throw Unreadable() }
        return nul
    }
}

private extension UnsafeRawBufferPointer {
    func bigEndian32(at offset: Int) -> UInt32 {
        UInt32(bigEndian: loadUnaligned(fromByteOffset: offset, as: UInt32.self))
    }

    func bigEndian16(at offset: Int) -> UInt16 {
        UInt16(bigEndian: loadUnaligned(fromByteOffset: offset, as: UInt16.self))
    }
}
