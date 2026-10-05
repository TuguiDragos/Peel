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
        "printf '%s\\n' \(line.quotedForTheShell) >> \(startupFile.pathForTheShell(home: home))"
    }

    /// Whether a line of `startupFile` that is not a comment names the file, however its spaces are written.
    public static func isSourced(_ url: URL, from startupFile: URL, home: URL) -> Bool {
        guard let data = BoundedRead.data(at: startupFile) else { return false }
        let name = url.path(below: home) ?? url.path(percentEncoded: false)
        return String(decoding: data, as: UTF8.self).split(separator: "\n").contains { line in
            let code = line.trimmingCharacters(in: .whitespaces)
            return !code.hasPrefix("#") && code.replacing("\\ ", with: " ").contains(name)
        }
    }

    /// Whether `startupFile` sets the prompt after the line that reads Peel's file, so zsh shows that one instead.
    public static func setsItsOwnPrompt(after url: URL, in startupFile: URL, home: URL) -> Bool {
        guard let data = BoundedRead.data(at: startupFile) else { return false }
        let name = url.path(below: home) ?? url.path(percentEncoded: false)
        let code = String(decoding: data, as: UTF8.self).split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.hasPrefix("#") }
        guard let peels = code.firstIndex(where: { $0.replacing("\\ ", with: " ").contains(name) }) else { return false }
        return code[(peels + 1)...].contains { $0.contains(/^(?:(?:export|typeset(?:\s+-g)?)\s+)?(?:PROMPT|PS1)=/) }
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
