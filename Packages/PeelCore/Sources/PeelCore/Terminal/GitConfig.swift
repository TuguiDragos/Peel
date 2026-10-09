public import Foundation
import PeelPrivileged

/// Git's global settings, read and changed through `git config --global`, Git's own command, in the home Peel
/// serves. `/usr/bin/git` is never run, since without the developer tools it asks macOS to install them.
public struct GitConfig: Sendable {
    public let executable: URL
    let home: URL

    public static func find(home: URL = .homeDirectory) async -> GitConfig? {
        let developer = await Subprocess.run("/usr/bin/xcode-select", ["-p"], environment: [:], timeout: 10)
        let folder: URL? = if case .success(let output) = developer, output.status == 0 {
            URL(filePath: output.text.trimmingCharacters(in: .whitespacesAndNewlines), directoryHint: .isDirectory)
        } else {
            nil
        }
        let homebrew = Homebrew.executableURL?.deletingLastPathComponent().deletingLastPathComponent()
        return find(developerFolder: folder, homebrewPrefix: homebrew, home: home)
    }

    static func find(developerFolder: URL?, homebrewPrefix: URL?, home: URL) -> GitConfig? {
        [developerFolder?.appending(path: "usr/bin/git"), homebrewPrefix?.appending(path: "bin/git")]
            .compactMap { $0 }
            .first { FileManager.default.isExecutableFile(atPath: $0.path(percentEncoded: false)) }
            .map { GitConfig(executable: $0, home: home) }
    }

    /// The global settings by their names in lowercase, a key written with no value as `.some(nil)`. None when
    /// there is no global file, and nil when Git could not read them.
    public func settings() async -> [String: String?]? {
        let files = [home.appending(path: ".gitconfig"), home.appending(path: ".config/git/config")]
        guard files.contains(where: { !$0.isMissing }) else { return [:] }
        guard case .success(let output) = await run(["config", "--global", "--list", "-z"]), output.status == 0 else { return nil }
        var settings: [String: String?] = [:]
        for entry in output.standardOutput.split(separator: 0) {
            let text = String(decoding: entry, as: UTF8.self)
            if let newline = text.firstIndex(of: "\n") {
                settings[text[..<newline].lowercased()] = String(text[text.index(after: newline)...])
            } else {
                settings[text.lowercased()] = .some(nil)
            }
        }
        return settings
    }

    /// The keys, in lowercase, that the files the global settings include set, through `include.path` or
    /// `includeIf.<condition>.path`, and the files those include. Git reads an included file where its include
    /// stands and the last value wins (`git help config`), so a key written at the end of the global file would win
    /// over the person's own in every folder their condition names.
    public func keysSetByIncludedFiles() async -> Set<String> {
        var keys: Set<String> = []
        var read: Set<String> = []
        var pending = Self.includes(in: await entries(["--global"]), home: home)
        while let file = pending.popLast(), read.count < 64 {
            let path = file.path(percentEncoded: false)
            guard read.insert(path).inserted, !file.isMissing else { continue }
            let entries = await entries(["--file", path])
            keys.formUnion(entries.filter { !$0.isAnInclude }.map(\.key))
            pending += Self.includes(in: entries, home: home)
        }
        return keys
    }

    private struct Entry {
        let file: String
        let key: String
        let value: String?

        var isAnInclude: Bool { key == "include.path" || key.hasPrefix("includeif.") && key.hasSuffix(".path") }
    }

    /// Each setting of `scope`, its key in lowercase, with the file it comes from.
    private func entries(_ scope: [String]) async -> [Entry] {
        guard case .success(let output) = await run(["config"] + scope + ["--list", "-z", "--show-origin"]),
              output.status == 0
        else { return [] }
        let fields = output.standardOutput.split(separator: 0, omittingEmptySubsequences: false)
            .map { String(decoding: $0, as: UTF8.self) }
        return stride(from: 0, to: fields.count - 1, by: 2).compactMap { index in
            guard fields[index].hasPrefix("file:") else { return nil }
            let entry = fields[index + 1]
            let newline = entry.firstIndex(of: "\n")
            return Entry(
                file: String(fields[index].dropFirst("file:".count)),
                key: String(entry[..<(newline ?? entry.endIndex)]).lowercased(),
                value: newline.map { String(entry[entry.index(after: $0)...]) }
            )
        }
    }

    /// The files `entries` include: a path beginning with `~/` is taken from the home and a relative one from the
    /// file its include is in, as Git takes them.
    private static func includes(in entries: [Entry], home: URL) -> [URL] {
        entries.filter(\.isAnInclude).compactMap { entry in
            guard let path = entry.value, !path.isEmpty else { return nil }
            if path.hasPrefix("~/") { return home.appending(path: String(path.dropFirst(2))) }
            if path.hasPrefix("/") { return URL(filePath: path) }
            return URL(filePath: entry.file).deletingLastPathComponent().appending(path: path)
        }
    }

    /// Every setting this Git knows, in lowercase, as `git help --config` lists them. A setting whose keys are not
    /// all known is never offered, so a Git that renames or drops one never gets a key it would ignore.
    public func knownKeys() async -> Set<String>? {
        guard case .success(let output) = await run(["help", "--config"]), output.status == 0 else { return nil }
        return Set(output.text.split(separator: "\n").map { $0.lowercased() })
    }

    public func set(_ key: String, to value: String) async -> Bool {
        guard case .success(let output) = await run(["config", "--global", "--replace-all", key, value]) else { return false }
        return output.status == 0
    }

    /// Removes every value of `key`. Git answers 5 when there is none, which is what was asked.
    public func remove(_ key: String) async -> Bool {
        guard case .success(let output) = await run(["config", "--global", "--unset-all", key]) else { return false }
        return output.status == 0 || output.status == 5
    }

    private func run(_ arguments: [String]) async -> Result<Subprocess.Output, Subprocess.Failure> {
        await Subprocess.run(
            executable.path(percentEncoded: false),
            arguments,
            environment: ["HOME": home.path(percentEncoded: false), "PATH": "/usr/bin:/bin:/usr/sbin:/sbin"],
            timeout: 10
        )
    }
}
