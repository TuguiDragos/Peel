import Darwin
public import Foundation
internal import PeelPrivileged

/// Works with paths Peel is given: expands `~` and shell wildcards into the files that exist, and finds the
/// names and spellings one file answers to, so paths can be compared safely.
public enum PathPattern {
    /// A folder path with no trailing slash, so two URLs for the same folder compare equal.
    public static func comparablePath(of url: URL) -> String {
        var path = url.standardizedFileURL.path(percentEncoded: false)
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        return path
    }

    /// The name the kernel gives the file at `url`: one spelling, with links resolved, or `url` unchanged when
    /// no name can be found. A path Peel is told about (by a cask, by an installer receipt) goes through this
    /// before it can become something to remove.
    static func canonical(_ url: URL) -> URL {
        name(of: url.path(percentEncoded: false)).map { URL(filePath: $0) } ?? url
    }

    /// The name the kernel gives what `path` leads to, read back from an open descriptor. macOS also accepts
    /// paths that name a file indirectly: `/.nofollow/` or `/.resolve/<flags>/` before any path, and
    /// `/.vol/<device>/<inode>` for a file by its numbers. On macOS 26, `realpath` resolves none of these,
    /// `getattrlist` only the last, and the Trash accepts a file under each. A descriptor names the object
    /// itself, however it was reached.
    static func kernelName(of path: String, followingLinks: Bool = true) -> String? {
        // Only what opens without consequence: a device has side effects, and a pipe waits for its other end.
        var info = stat()
        guard (followingLinks ? stat(path, &info) : lstat(path, &info)) == 0 else { return nil }
        guard [S_IFDIR, S_IFREG, S_IFLNK].contains(info.st_mode & S_IFMT) else { return nil }
        let descriptor = open(path, O_EVTONLY | O_NONBLOCK | O_CLOEXEC | (followingLinks ? 0 : O_SYMLINK))
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        guard fcntl(descriptor, F_GETPATH, &buffer) == 0 else { return nil }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    /// The kernel's name when `path` can be opened, or `realpath`'s when it cannot: a folder macOS keeps from
    /// Peel (Mail, without Full Disk Access) does not open, but `realpath` still resolves its links.
    private static func name(of path: String) -> String? {
        kernelName(of: path) ?? realName(of: path)
    }

    /// `realpath`'s name for `path`: links resolved and each name spelled as on disk, found without opening anything.
    private static func realName(of path: String) -> String? {
        guard let real = realpath(path, nil) else { return nil }
        defer { free(real) }
        return String(cString: real)
    }

    /// Where the item at `path` sits, or would sit. The deepest existing folder on the way is named by the
    /// kernel (links resolved, spelled as on disk), and the rest is appended as written. The last component is
    /// never followed, since a move takes a link and not what it points to. Nil when the part appended holds
    /// `.` or `..`, which cannot be resolved without the folders.
    static func located(_ path: String) -> String? {
        located(path, naming: name(of:))
    }

    /// `located`, with `realpath` naming the folders. Opening a folder inside another app's container makes macOS ask
    /// the person for that app's data, and looking a path up there does not, so this is what the guard asks of the
    /// places it protects. `realpath` gives the kernel's answer for any path but one that begins with `/.vol/`,
    /// `/.nofollow/` or `/.resolve/`, and a place named from a home folder never does.
    static func locatedWithoutOpening(_ path: String) -> String? {
        located(path, naming: realName(of:))
    }

    private static func located(_ path: String, naming name: (String) -> String?) -> String? {
        guard path != "/" else { return path }
        var ancestor = (path as NSString).deletingLastPathComponent
        var rest = [(path as NSString).lastPathComponent]
        while true {
            if let folder = name(ancestor) {
                guard !rest.contains(where: { $0 == "." || $0 == ".." }) else { return nil }
                return (folder == "/" ? "" : folder) + "/" + rest.reversed().joined(separator: "/")
            }
            guard ancestor != "/", !ancestor.isEmpty else { return nil }
            rest.append((ancestor as NSString).lastPathComponent)
            ancestor = (ancestor as NSString).deletingLastPathComponent
        }
    }

    /// True when `url`, as written or as the kernel names it, is data `ProtectedData` refuses (mail, keys,
    /// iCloud Drive and the like). Whatever a pattern says, such a path is never a leftover.
    static func isIrreplaceable(_ url: URL, home: String) -> Bool {
        let path = url.path(percentEncoded: false)
        return ProtectedData.refuses(path, home: home)
            || ProtectedData.refuses(canonical(url).path(percentEncoded: false), home: home)
    }

    /// Where a pattern comes from, which says how it is read.
    enum Source {
        /// Peel's own, a shell pattern for a tool's folders: every match counts.
        case peel
        /// A cask's, read as Homebrew reads it with Ruby's `Dir.glob`: `{a,b}` for each alternative, a backslash
        /// quoting the next character, and `**/` for any number of folders but hidden ones and links. Being data from
        /// elsewhere, it keeps `glob`'s limits: 128 paths on macOS whatever `gl_matchc` says (`GLOB_LIMIT_STAT` in
        /// Libc's `glob.c`), and as many entries read as `GLOB_LIMIT_READDIR`, for a `**/` too.
        case cask
    }

    private static let entriesAStarReads = 16_384

    /// The existing files `pattern` names, leaving out irreplaceable ones (`isIrreplaceable`). A pattern without a
    /// leading `/` or `~` is read relative to `home`.
    static func expand(_ pattern: String, home: URL, from source: Source) -> [URL] {
        let root = comparablePath(of: home)
        var path = pattern
        if path.hasPrefix("~") {
            path = root + path.dropFirst()
        } else if !path.hasPrefix("/") {
            path = root + "/" + path
        }
        guard source == .cask, path.contains("/**/") else { return matches(of: path, root: root, source: source) }
        var unread = entriesAStarReads
        return matchesThroughStars(of: path, root: root, unread: &unread)
    }

    /// What a cask's `path` names when its first `**/` stands for the folder before it and every folder below.
    private static func matchesThroughStars(of path: String, root: String, unread: inout Int) -> [URL] {
        guard let star = path.range(of: "/**/") else { return matches(of: path, root: root, source: .cask) }
        let rest = path[star.upperBound...]
        var found: [URL] = []
        for start in matches(of: String(path[..<star.lowerBound]), root: root, source: .cask) where start.isRealFolder {
            for folder in folders(from: start, unread: &unread) {
                let inside = quoted(comparablePath(of: folder)) + "/" + rest
                found += matchesThroughStars(of: inside, root: root, unread: &unread)
            }
        }
        return found
    }

    /// `start` and every folder below it, level by level, but hidden ones and links, until `unread` entries are read.
    private static func folders(from start: URL, unread: inout Int) -> [URL] {
        var found = [start]
        var level = [start]
        while !level.isEmpty {
            var below: [URL] = []
            for folder in level where unread > 0 {
                let entries = (try? FileManager.default.contentsOfDirectory(
                    at: folder, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]
                )) ?? []
                unread -= entries.count
                below += entries.filter { !$0.lastPathComponent.hasPrefix(".") && $0.isRealFolder }
                    .sorted { $0.lastPathComponent < $1.lastPathComponent }
            }
            found += below
            level = below
        }
        return found
    }

    /// `path` with every character `glob` reads as a pattern quoted, so a folder's own name is taken as written.
    private static func quoted(_ path: String) -> String {
        path.reduce(into: "") { text, character in
            if "\\*?[]{}".contains(character) { text.append("\\") }
            text.append(character)
        }
    }

    private static func matches(of path: String, root: String, source: Source) -> [URL] {
        // A path with no wildcard (`*`, `?`, and for a cask `{`) that exists is taken as written, so a bracket in a
        // real name (`App [Beta]`) is not read as a character class.
        let isPattern = path.contains("*") || path.contains("?") || (source == .cask && path.contains("{"))
        if !isPattern, FileManager.default.fileExists(atPath: path) {
            let url = entry(named: path)
            return isIrreplaceable(url, home: root) ? [] : [url]
        }
        guard isPattern || path.contains("[") else { return [] }

        var results = glob_t()
        defer { globfree(&results) }
        let flags = switch source {
        case .peel: GLOB_NOSORT | GLOB_NOESCAPE
        case .cask: GLOB_NOSORT | GLOB_BRACE | GLOB_LIMIT
        }
        // At its limit, `glob` returns GLOB_NOSPACE with the paths found so far.
        let code = glob(path, flags, nil, &results)
        guard code == 0 || code == GLOB_NOSPACE, results.gl_pathv != nil else { return [] }
        return (0..<Int(results.gl_pathc)).compactMap { index in
            guard let pointer = results.gl_pathv[index] else { return nil }
            let url = entry(named: String(cString: pointer))
            return isIrreplaceable(url, home: root) ? nil : url
        }
    }

    /// The entry `path` names. A path that ends in `/` names folders only, and the kernel follows a link to what it
    /// leads to when the slash is kept, so the entry is named without it.
    private static func entry(named path: String) -> URL {
        URL(filePath: path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path)
    }
}
