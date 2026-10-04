public import Foundation
import PeelPrivileged

/// The zsh file Peel writes the Shell tab's settings into. The shell reads it only through the line the person
/// adds to their own startup file, so Peel never edits that file, and putting the settings back empties this one.
public enum ShellFile {
    static let header = "# Written by Peel. Change it on the Shell tab of the Terminal page in Peel."
    static let completionSystem = "(( $+functions[compdef] )) || { autoload -Uz compinit && compinit }"
    private static let maximumBytes = 64 * 1_024

    public static func url(in folder: URL) -> URL {
        folder.appending(path: "Terminal/zshrc", directoryHint: .notDirectory)
    }

    public static func contents(of settings: Set<ShellSetting>) -> String {
        var lines = [header]
        for setting in ShellSetting.allCases where settings.contains(setting) {
            if setting.group == .completion, !lines.contains(completionSystem) {
                lines.append(completionSystem)
            }
            lines += setting.lines
        }
        return lines.joined(separator: "\n") + "\n"
    }

    public static func settings(in contents: String) -> Set<ShellSetting> {
        let lines = Set(contents.split(separator: "\n").map(String.init))
        return Set(ShellSetting.allCases.filter { $0.lines.allSatisfy(lines.contains) })
    }

    /// The settings in the file, none when it is not there, and nil when it is there and cannot be read.
    public static func read(_ url: URL) -> Set<ShellSetting>? {
        if url.isMissing {
            return []
        }
        return BoundedRead.data(at: url, maximum: maximumBytes).map { settings(in: String(decoding: $0, as: UTF8.self)) }
    }

    public static func write(_ settings: Set<ShellSetting>, to url: URL) -> Bool {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(contents(of: settings).utf8).write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    public static func line(sourcing url: URL, home: URL) -> String {
        let path = "\"" + (insideHome(url, home: home).map { "$HOME/" + escaped($0) } ?? escaped(url.path(percentEncoded: false))) + "\""
        return "[[ -r \(path) ]] && source \(path)"
    }

    /// Whether a line of `startupFile` that is not a comment names the file, however its spaces are written.
    public static func isSourced(_ url: URL, from startupFile: URL, home: URL) -> Bool {
        guard let data = BoundedRead.data(at: startupFile) else { return false }
        let name = insideHome(url, home: home) ?? url.path(percentEncoded: false)
        return String(decoding: data, as: UTF8.self).split(separator: "\n").contains { line in
            let code = line.trimmingCharacters(in: .whitespaces)
            return !code.hasPrefix("#") && code.replacing("\\ ", with: " ").contains(name)
        }
    }

    private static func insideHome(_ url: URL, home: URL) -> String? {
        let names = PathComponents.of(url.path(percentEncoded: false))
        let homeNames = PathComponents.of(home.path(percentEncoded: false))
        guard PathComponents.isPath(url.path(percentEncoded: false), inside: home.path(percentEncoded: false)) else { return nil }
        return names.dropFirst(homeNames.count).joined(separator: "/")
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
