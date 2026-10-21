public import Foundation

/// The zsh file Peel writes the Shell tab's settings into. The shell reads it only through the line the person
/// adds to their own startup file, so Peel never edits that file, and putting the settings back empties this one.
public enum ShellFile {
    static let header = "# Written by Peel. Change it on the Shell tab of the Terminal page in Peel."
    static let completionSystem = "(( $+functions[compdef] )) || { autoload -Uz compinit && compinit }"
    private static let maximumBytes = 64 * 1_024

    public struct Choices: Equatable, Sendable {
        public var settings: Set<ShellSetting>
        public var prompt: Prompt?

        public init(settings: Set<ShellSetting> = [], prompt: Prompt? = nil) {
            self.settings = settings
            self.prompt = prompt
        }
    }

    public static func url(in folder: URL) -> URL {
        folder.appending(path: "Terminal/zshrc", directoryHint: .notDirectory)
    }

    public static func contents(of choices: Choices) -> String {
        var lines = [header]
        for setting in ShellSetting.allCases where choices.settings.contains(setting) {
            if setting.group == .completion, !lines.contains(completionSystem) {
                lines.append(completionSystem)
            }
            lines += setting.lines
        }
        lines += choices.prompt?.lines ?? []
        return lines.joined(separator: "\n") + "\n"
    }

    public static func choices(in contents: String) -> Choices {
        let lines = Set(contents.split(separator: "\n").map(String.init))
        let isIn: (Set<String>) -> Bool = { $0.isSubset(of: lines) }
        return Choices(
            settings: Set(ShellSetting.allCases.filter { isIn(Set($0.lines)) }),
            prompt: Prompt.all.first { isIn(Set($0.lines)) }
        )
    }

    /// The choices in the file, none when it is not there, and nil when it is there and cannot be read.
    public static func read(_ url: URL) -> Choices? {
        if url.isMissing {
            return Choices()
        }
        return BoundedRead.data(at: url, maximum: maximumBytes).map { choices(in: String(decoding: $0, as: UTF8.self)) }
    }

    public static func write(_ choices: Choices, to url: URL) -> Bool {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data(contents(of: choices).utf8).write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    public static func line(sourcing url: URL, home: URL) -> String {
        let path = "\"" + (url.path(below: home).map { "$HOME/" + escaped($0) } ?? escaped(url.path(percentEncoded: false))) + "\""
        return "[[ -r \(path) ]] && source \(path)"
    }

    /// The command that adds `line` at the end of `startupFile`, which it makes when there is none.
    public static func command(adding line: String, to startupFile: URL, home: URL) -> String {
        ShellCommand.appending([line], to: startupFile, home: home)
    }

    /// Whether a line of `startupFile` reads the file.
    public static func isSourced(_ url: URL, from startupFile: URL, home: URL) -> Bool {
        guard let data = BoundedRead.data(at: startupFile) else { return false }
        return String(decoding: data, as: UTF8.self).split(separator: "\n")
            .contains { sources(String($0), url, home: home) }
    }

    /// Whether `line` reads the file: `source` or `.` with the file's path as its argument, written from `$HOME`,
    /// `${HOME}` or `~`, or whole, in quotes or not, its spaces escaped or not, and not in a comment. Peel's own line
    /// tests the file first, `[[ -r … ]] && source …`, and counts only when that test starts a command: run into the
    /// line before it, as happened in a file whose last line had no newline, zsh fails on the line and never reaches
    /// the `source`.
    static func sources(_ line: String, _ url: URL, home: URL) -> Bool {
        let code = line.trimmingCharacters(in: .whitespaces).replacing("\\ ", with: " ")
        guard !code.hasPrefix("#") else { return false }
        let escaped = NSRegularExpression.escapedPattern(for:)
        let whole = "[\"']?" + escaped(url.path(percentEncoded: false)) + "[\"']?"
        let fromHome = url.path(below: home).map { below in
            "\"?(?:\\$HOME|\\$\\{HOME\\}|~)/" + escaped(below) + "\"?"
        }
        let path = "(?:" + ([fromHome, whole].compactMap { $0 }).joined(separator: "|") + ")"
        let start = #"(?:^|[\s;&|(){])"#
        let test = #"\[\[\s+-r\s+"# + path + #"\s+\]\]\s*&&\s*"#
        let reads = #"(?:source|\.)\s+"# + path + #"(?:$|[\s;&|)}#])"#
        let contains = { (pattern: String) in (try? Regex(pattern)).map { code.contains($0) } ?? false }
        return contains(test) ? contains(start + test + reads) : contains(start + reads)
    }

    /// Whether `startupFile` sets the prompt after the line that reads Peel's file, so zsh shows that one instead.
    public static func setsItsOwnPrompt(after url: URL, in startupFile: URL, home: URL) -> Bool {
        guard let data = BoundedRead.data(at: startupFile) else { return false }
        let lines = String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init)
        guard let peels = lines.firstIndex(where: { sources($0, url, home: home) }) else { return false }
        return lines[(peels + 1)...].contains {
            $0.trimmingCharacters(in: .whitespaces).contains(/^(?:(?:export|typeset(?:\s+-g)?)\s+)?(?:PROMPT|PS1)=/)
        }
    }

    private static func escaped(_ text: String) -> String {
        text.reduce(into: "") { result, character in
            if "\"\\`$".contains(character) {
                result.append("\\")
            }
            result.append(character)
        }
    }
}
