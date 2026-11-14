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

    /// Why the file at `url` can't be read, or nil when it can, or isn't there.
    public static func whyUnreadable(_ url: URL) -> FileProblem? {
        url.isMissing ? nil : BoundedRead.whyUnreadable(url, maximum: maximumBytes)
    }

    /// Writes `choices` to `url`, and answers why it couldn't, or nil once it did.
    @discardableResult
    public static func write(_ choices: Choices, to url: URL) -> FileProblem? {
        do {
            try PeelFolder.write(Data(contents(of: choices).utf8), to: url)
            return nil
        } catch {
            return FileProblem(error)
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
        let reading = LineReading(of: url, home: home)
        return String(decoding: data, as: UTF8.self).split(separator: "\n").contains { reading.reads(String($0)) }
    }

    /// Whether a line reads the file with `source` or `.`, outside a comment. Made once per file: patterns are costly.
    /// Peel's `[[ -r … ]] && source …` counts only where its test starts a command, or zsh never reaches the `source`.
    struct LineReading {
        private let test: Regex<AnyRegexOutput>?
        private let readsAfterTheTest: Regex<AnyRegexOutput>?
        private let reads: Regex<AnyRegexOutput>?

        init(of url: URL, home: URL) {
            let escaped = NSRegularExpression.escapedPattern(for:)
            let whole = "[\"']?" + escaped(url.path(percentEncoded: false)) + "[\"']?"
            // `~` stands for the home only outside quotes, `$HOME` inside double quotes too.
            let fromHome = url.path(below: home).map { below in
                let rest = "/" + escaped(below)
                return "(?:\"(?:\\$HOME|\\$\\{HOME\\})" + rest + "\"|(?:\\$HOME|\\$\\{HOME\\}|~)" + rest + ")"
            }
            let path = "(?:" + ([fromHome, whole].compactMap { $0 }).joined(separator: "|") + ")"
            let start = #"(?:^|[\s;&|(){])"#
            let test = #"\[\[\s+-r\s+"# + path + #"\s+\]\]\s*&&\s*"#
            let reads = #"(?:source|\.)\s+"# + path + #"(?:$|[\s;&|)}#])"#
            self.test = try? Regex(test)
            readsAfterTheTest = try? Regex(start + test + reads)
            self.reads = try? Regex(start + reads)
        }

        func reads(_ line: String) -> Bool {
            let code = Self.withoutComment(line).trimmingCharacters(in: .whitespaces).replacing("\\ ", with: " ")
            let contains = { (pattern: Regex<AnyRegexOutput>?) in pattern.map { code.contains($0) } ?? false }
            return contains(test) ? contains(readsAfterTheTest) : contains(reads)
        }

        /// The line before the `#` that starts a comment, as zsh reads a startup file: one that begins a word, outside
        /// quotes.
        static func withoutComment(_ line: String) -> Substring {
            var quote: Character?
            var isEscaped = false
            var previous: Character = " "
            for index in line.indices {
                let character = line[index]
                defer { previous = character }
                if isEscaped {
                    isEscaped = false
                } else if let open = quote {
                    if character == open { quote = nil } else if character == "\\", open == "\"" { isEscaped = true }
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" || character == "'" {
                    quote = character
                } else if character == "#", previous.isWhitespace {
                    return line[..<index]
                }
            }
            return line[...]
        }
    }

    /// Whether `startupFile` sets the prompt after the line that reads Peel's file, so zsh shows that one instead.
    public static func setsItsOwnPrompt(after url: URL, in startupFile: URL, home: URL) -> Bool {
        guard let data = BoundedRead.data(at: startupFile) else { return false }
        let lines = String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init)
        let reading = LineReading(of: url, home: home)
        guard let peels = lines.firstIndex(where: { reading.reads($0) }) else { return false }
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
