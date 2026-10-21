public import Foundation
import PeelPrivileged

/// The SSH settings file Peel writes the SSH tab's settings into. ssh reads it only through the lines the person
/// adds at the end of `~/.ssh/config`, and since ssh keeps the first value it finds for each option, what the
/// person set for a server earlier in that file stays in force.
public enum SSHFile {
    static let header = "# Written by Peel. Change it on the SSH tab of the Terminal page in Peel."
    private static let maximumBytes = 64 * 1_024

    public static func url(in folder: URL) -> URL {
        folder.appending(path: "Terminal/ssh_config", directoryHint: .notDirectory)
    }

    /// The file for `settings`. The `IgnoreUnknown` line goes first and is no setting's own line, so a file written
    /// without it still reads as the settings in it.
    public static func contents(of settings: Set<SSHSetting>) -> String {
        let chosen = SSHSetting.allCases.filter(settings.contains)
        let onlyApples = chosen.flatMap(\.onlyApplesSSHKnows)
        let ignored = onlyApples.isEmpty ? [] : ["IgnoreUnknown " + onlyApples.joined(separator: ",")]
        return ([header] + ignored + chosen.flatMap(\.lines)).joined(separator: "\n") + "\n"
    }

    /// The file as this version writes it, when `contents` is exactly what an earlier version wrote, which had no
    /// `IgnoreUnknown` line. A file changed by hand is nil, and so is one already as this version writes it.
    public static func update(of contents: String) -> String? {
        let settings = settings(in: contents)
        let earlier = ([header] + SSHSetting.allCases.filter(settings.contains).flatMap(\.lines))
            .joined(separator: "\n") + "\n"
        let now = self.contents(of: settings)
        return contents == earlier && contents != now ? now : nil
    }

    /// Writes the file at `url` again as this version writes it, when an earlier version wrote it.
    public static func bringUpToDate(_ url: URL) {
        guard let data = BoundedRead.data(at: url, maximum: maximumBytes),
              let updated = update(of: String(decoding: data, as: UTF8.self))
        else { return }
        try? Data(updated.utf8).write(to: url, options: .atomic)
    }

    public static func settings(in contents: String) -> Set<SSHSetting> {
        let lines = Set(contents.split(separator: "\n").map(String.init))
        return Set(SSHSetting.allCases.filter { Set($0.lines).isSubset(of: lines) })
    }

    /// The settings in the file, none when it is not there, and nil when it is there and cannot be read.
    public static func read(_ url: URL) -> Set<SSHSetting>? {
        if url.isMissing {
            return []
        }
        return BoundedRead.data(at: url, maximum: maximumBytes).map {
            settings(in: String(decoding: $0, as: UTF8.self))
        }
    }

    public static func write(_ settings: Set<SSHSetting>, to url: URL) -> Bool {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data(contents(of: settings).utf8).write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    /// The lines that make ssh read the file. `Match all` first, so they apply to every server even after a `Host`
    /// block, where an `Include` alone would apply only to that block's servers.
    public static func lines(including url: URL, home: URL) -> [String] {
        let path = url.path(below: home).map { "~/" + $0 } ?? url.path(percentEncoded: false)
        return ["Match all", "  Include \"\(path.replacing("\\", with: "\\\\").replacing("\"", with: "\\\""))\""]
    }

    /// The command that adds `lines` at the end of `config`, making the folder it is in, closed to everyone else as
    /// ssh wants it, and the file itself when they are not there.
    public static func command(adding lines: [String], to config: URL, home: URL) -> String {
        let folder = config.deletingLastPathComponent().pathForTheShell(home: home)
        return "mkdir -p -m 700 \(folder) && " + ShellCommand.appending(lines, to: config, home: home)
    }

    /// Whether an `Include` line of `config` names the file, however its spaces are written.
    public static func isIncluded(_ url: URL, from config: URL, home: URL) -> Bool {
        guard let data = BoundedRead.data(at: config) else { return false }
        let name = url.path(below: home) ?? url.path(percentEncoded: false)
        return String(decoding: data, as: UTF8.self).split(separator: "\n").contains { line in
            let code = line.trimmingCharacters(in: .whitespaces)
            return code.lowercased().hasPrefix("include") && code.replacing("\\ ", with: " ").contains(name)
        }
    }

    /// The settings the ssh on this Mac accepts, asked on its command line so nothing is written to try them, or nil
    /// when ssh answered none of the questions.
    public static func accepted(ssh: String = "/usr/bin/ssh") async -> Set<SSHSetting>? {
        var accepted: Set<SSHSetting> = []
        var answered = false
        for setting in SSHSetting.allCases {
            let options = setting.lines.flatMap { ["-o", $0] }
            let answer = await Subprocess.run(ssh, ["-G", "-F", "/dev/null"] + options + ["peel.invalid"], environment: [:], timeout: 10)
            guard case .success(let output) = answer else { continue }
            answered = true
            if output.status == 0 {
                accepted.insert(setting)
            }
        }
        return answered ? accepted : nil
    }
}
