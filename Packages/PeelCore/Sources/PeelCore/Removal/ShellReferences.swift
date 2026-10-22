public import Foundation

/// The lines of the shell startup files that still name something a removal moved, such as a path exported or
/// sourced from inside an app's bundle. Peel reads these files and never changes them: it points to the line.
public enum ShellReferences {
    public struct Reference: Sendable, Hashable {
        public let file: URL
        public let line: Int

        public init(file: URL, line: Int) {
            self.file = file
            self.line = line
        }
    }

    /// At most this much of a startup file is read; a bigger one is passed over.
    static let maximumBytes = 1_048_576

    @concurrent
    public static func find(naming moved: [URL], home: URL = .homeDirectory) async -> [Reference] {
        let spellings = moved.flatMap { spellings(of: $0, home: home) }.map { Array($0.lowercased().utf8) }
        guard !spellings.isEmpty else { return [] }
        var references: [Reference] = []
        for file in await startupFiles(home: home) {
            guard let data = BoundedRead.data(at: file, maximum: maximumBytes) else { continue }
            let lines = String(decoding: data, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: false)
            for (index, line) in lines.enumerated() where !line.drop(while: \.isWhitespace).hasPrefix("#") {
                let line = Array(line.lowercased().utf8)
                if spellings.contains(where: { holdsWhole($0, in: line) }) {
                    references.append(Reference(file: file, line: index + 1))
                }
            }
        }
        return references
    }

    /// Whether `line` holds `path` whole, or followed by a slash into it, both in UTF-8: `~/.config/pad` is not in
    /// `~/.config/padlock`, nor `/Applications/Pad.app` in `~/Applications/Pad.app`.
    static func holdsWhole(_ path: [UInt8], in line: [UInt8]) -> Bool {
        line.withUnsafeBytes { haystack in
            path.withUnsafeBytes { needle in
                guard let start = haystack.baseAddress, let target = needle.baseAddress, !path.isEmpty else {
                    return false
                }
                var offset = 0
                while let found = memmem(start + offset, line.count - offset, target, path.count) {
                    let begin = UnsafeRawPointer(found) - start
                    let end = begin + path.count
                    if begin == 0 || startsAWord.contains(line[begin - 1]),
                       end == line.count || endsAPath.contains(line[end]) {
                        return true
                    }
                    offset = begin + 1
                }
                return false
            }
        }
    }

    private static let startsAWord = Set(" \t\r\u{0B}\u{0C}\"'`=:;,|&({[<>".utf8)

    /// A backslash or a dollar sign goes on with the name, as an escaped space or a variable does.
    private static let endsAPath = Set(" \t\r\u{0B}\u{0C}/\"'`:;,|&()}]<>".utf8)

    /// The files zsh, bash and fish read when a shell starts: zsh's `.zshenv` where the session's ZDOTDIR or the
    /// home folder puts it, the other three in the folder zsh names once `.zshenv` has run, and the rest in the home
    /// folder.
    static func startupFiles(home: URL) async -> [URL] {
        var files: [URL] = []
        let zdotdir = ShellSessions.sessionZDOTDIR
        if let zsh = ShellSessions.of(terminalSetting: nil, loginShell: "/bin/zsh", zdotdir: zdotdir, home: home),
           case .zsh(let zshenv) = zsh {
            files.append(zshenv)
            let folder = (await zsh.zshrc(home: home, zdotdir: zdotdir) ?? zshenv).deletingLastPathComponent()
            files += [".zprofile", ".zshrc", ".zlogin"].map { folder.appending(path: $0, directoryHint: .notDirectory) }
        }
        files += [".bash_profile", ".bashrc", ".profile", ".config/fish/config.fish"].map {
            home.appending(path: $0, directoryHint: .notDirectory)
        }
        var seen: Set<String> = []
        return files.filter { seen.insert($0.path(percentEncoded: false)).inserted }
    }

    /// A path as a shell line writes it: whole, or with `~` or `$HOME` for the home folder, each also with its
    /// spaces escaped.
    static func spellings(of url: URL, home: URL) -> [String] {
        let path = trimmed(url.path(percentEncoded: false))
        let homePath = trimmed(home.path(percentEncoded: false))
        var spellings = [path]
        if path.hasPrefix(homePath + "/") {
            let rest = path.dropFirst(homePath.count)
            spellings += ["~" + rest, "$HOME" + rest, "${HOME}" + rest]
        }
        return spellings + spellings.filter { $0.contains(" ") }.map { $0.replacingOccurrences(of: " ", with: "\\ ") }
    }

    private static func trimmed(_ path: String) -> String {
        path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }
}
