import Darwin
public import Foundation
internal import PeelPrivileged

/// Works with paths Peel is given: expands `~` and shell wildcards into the files that exist, and finds the
/// names and spellings one file answers to, so paths can be compared safely.
public enum PathPattern {
    static let maximumMatches = 200

    /// A folder path with no trailing slash, so two URLs for the same folder compare equal.
    public static func comparablePath(of url: URL) -> String {
        var path = url.standardizedFileURL.path(percentEncoded: false)
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        return path
    }

    /// macOS keeps `/var`, `/tmp` and `/etc` as symbolic links into `/private`, so the same file has two
    /// names. Both are needed to compare paths, and resolving the link is no help for a file that is not
    /// there to resolve.
    private static let privateLinks = ["/var", "/tmp", "/etc"]

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
        if let name = kernelName(of: path) { return name }
        guard let real = realpath(path, nil) else { return nil }
        defer { free(real) }
        return String(cString: real)
    }

    /// Where the item at `path` sits, or would sit. The deepest existing folder on the way is named by the
    /// kernel (links resolved, spelled as on disk), and the rest is appended as written. The last component is
    /// never followed, since a move takes a link and not what it points to. Nil when the part appended holds
    /// `.` or `..`, which cannot be resolved without the folders.
    static func located(_ path: String) -> String? {
        guard path != "/" else { return path }
        var ancestor = (path as NSString).deletingLastPathComponent
        var rest = [(path as NSString).lastPathComponent]
        while true {
            if let folder = name(of: ancestor) {
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

    /// Every name the same file answers to, in lowercase: with and without `/private`, and with links resolved.
    /// A Mac disk is case-insensitive unless formatted otherwise, so `~/Library/mail` is `~/Library/Mail`.
    /// Comparing one spelling only would let a protected path be reached by writing it differently.
    static func spellings(of path: String) -> Set<String> {
        var names = privateNames(of: path)
        let resolved = (path as NSString).resolvingSymlinksInPath
        if resolved != path {
            names.formUnion(privateNames(of: resolved))
        }
        return Set(names.map { $0.lowercased() })
    }

    private static func privateNames(of path: String) -> Set<String> {
        for link in privateLinks {
            if PathComponents.isPath(path, atOrInside: link) {
                return [path, "/private" + path]
            }
            let inPrivate = "/private" + link
            if PathComponents.isPath(path, atOrInside: inPrivate) {
                return [path, String(path.dropFirst("/private".count))]
            }
        }
        return [path]
    }

    /// The existing files `pattern` names, at most `maximum`, leaving out irreplaceable ones (`isIrreplaceable`).
    /// A pattern without a leading `/` or `~` is read relative to `home`.
    static func expand(_ pattern: String, home: URL, maximum: Int = maximumMatches) -> [URL] {
        let root = comparablePath(of: home)
        var path = pattern
        if path.hasPrefix("~") {
            path = root + path.dropFirst()
        } else if !path.hasPrefix("/") {
            path = root + "/" + path
        }

        // A path without `*` or `?` that exists is taken as written, so a bracket in a real name
        // (`App [Beta]`) is not read as a character class.
        let isPattern = path.contains("*") || path.contains("?")
        if !isPattern, FileManager.default.fileExists(atPath: path) {
            let url = entry(named: path)
            return isIrreplaceable(url, home: root) ? [] : [url]
        }
        guard isPattern || path.contains("[") else { return [] }

        var results = glob_t()
        defer { globfree(&results) }
        // GLOB_LIMIT keeps a pattern from walking the whole disk. It stops at `gl_matchc` paths (`man 3 glob`),
        // and on macOS 26 at 128 even when `gl_matchc` is higher. At the limit, `glob` returns GLOB_NOSPACE
        // with the paths found so far.
        results.gl_matchc = Int32(clamping: maximum)
        let code = glob(path, GLOB_NOSORT | GLOB_LIMIT | GLOB_NOESCAPE, nil, &results)
        guard code == 0 || code == GLOB_NOSPACE, results.gl_pathv != nil else { return [] }
        return (0..<Int(results.gl_pathc)).prefix(maximum).compactMap { index in
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
