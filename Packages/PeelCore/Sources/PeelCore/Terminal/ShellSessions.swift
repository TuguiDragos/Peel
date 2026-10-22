public import Foundation
import PeelPrivileged

public enum ShellSessions: Sendable, Equatable {
    case zsh(startupFile: URL)
    case bash

    public static func inTerminal(
        _ terminal: some TerminalSettingsStoring, home: URL = .homeDirectory
    ) -> ShellSessions? {
        of(terminalSetting: terminal.shell(), loginShell: loginShell(), zdotdir: sessionZDOTDIR, home: home)
    }

    /// The ZDOTDIR of the session Peel runs in, which Terminal's zsh starts with too, since launchd starts both.
    static var sessionZDOTDIR: String? {
        ProcessInfo.processInfo.environment["ZDOTDIR"]
    }

    static func of(terminalSetting: String?, loginShell: String?, zdotdir: String?, home: URL) -> ShellSessions? {
        let shell = terminalSetting.flatMap { $0.isEmpty ? nil : $0 } ?? loginShell
        switch shell.map({ String(URL(filePath: $0).lastPathComponent.prefix { $0 != " " }) }) {
        case "zsh"?:
            let folder = zdotdir.flatMap { $0.isEmpty ? nil : URL(filePath: $0, directoryHint: .isDirectory) } ?? home
            return .zsh(startupFile: folder.appending(path: ".zshenv", directoryHint: .notDirectory))
        case "bash"?:
            return .bash
        default:
            return nil
        }
    }

    /// The `.zshrc` zsh reads, where the line that sources Peel's file goes: in the folder `ZDOTDIR` names once
    /// `.zshenv` has run, since `.zshenv` may set it (`man zsh`, STARTUP/SHUTDOWN FILES). zsh is asked with `-c`, which
    /// reads `.zshenv` and no other startup file, and the folder of `.zshenv` stands when it doesn't answer.
    public func zshrc(home: URL = .homeDirectory) async -> URL? {
        await zshrc(home: home, zdotdir: Self.sessionZDOTDIR)
    }

    /// `zdotdir` is set for zsh only when the session sets it, since `.zshenv` may keep a ZDOTDIR it finds
    /// (`${ZDOTDIR:-$HOME/.config/zsh}`).
    func zshrc(home: URL, zdotdir: String?) async -> URL? {
        guard case .zsh(let zshenv) = self else { return nil }
        let folder = zshenv.deletingLastPathComponent()
        // With no slash at the end, which `"$HOME/.config/zsh"` would double.
        var environment = [
            "HOME": (home.path(percentEncoded: false) as NSString).standardizingPath,
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
        ]
        if let zdotdir, !zdotdir.isEmpty {
            environment["ZDOTDIR"] = (zdotdir as NSString).standardizingPath
        }
        let answer = await Subprocess.run(
            "/bin/zsh", ["-c", #"print -r -- "${ZDOTDIR:-$HOME}""#], environment: environment, timeout: 10
        )
        // What `.zshenv` itself prints comes first, so the answer is the last line.
        let named: String? = if case .success(let output) = answer, output.status == 0,
            let line = output.text.split(separator: "\n").last, line.hasPrefix("/") { String(line) } else { nil }
        return (named.map { URL(filePath: $0, directoryHint: .isDirectory) } ?? folder)
            .appending(path: ".zshrc", directoryHint: .notDirectory)
    }

    /// The prompt a new zsh shows, as zsh itself answers.
    public struct ShownPrompt: Equatable, Sendable {
        /// What `PROMPT` holds once every startup file has run and the hooks zsh runs before a prompt have run.
        public let prompt: String
        /// The functions zsh runs before each prompt that changed it, in the order they ran: a prompt they set wins
        /// over any `PROMPT=` line, wherever it stands.
        public let setBeforeEachCommandBy: [String]
    }

    public func promptShown(home: URL = .homeDirectory) async -> ShownPrompt? {
        await promptShown(home: home, zdotdir: Self.sessionZDOTDIR)
    }

    /// Asks the login shell, as Terminal starts it, for its prompt once every startup file and `precmd` hook has
    /// run, read between marks so the files' output is skipped. Nil when it isn't zsh or doesn't answer in time.
    func promptShown(home: URL, zdotdir: String?) async -> ShownPrompt? {
        guard case .zsh = self else { return nil }
        var environment = [
            "HOME": (home.path(percentEncoded: false) as NSString).standardizingPath,
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "TERM": "xterm-256color",
        ]
        if let zdotdir, !zdotdir.isEmpty {
            environment["ZDOTDIR"] = (zdotdir as NSString).standardizingPath
        }
        let script = """
            typeset -g peel_was="$PROMPT"; typeset -ga peel_by=()
            for peel_f in $precmd_functions; do
                "$peel_f" 2>/dev/null
                if [[ "$PROMPT" != "$peel_was" ]]; then peel_by+=("$peel_f"); peel_was="$PROMPT"; fi
            done
            if (( $+functions[precmd] )); then
                precmd 2>/dev/null
                if [[ "$PROMPT" != "$peel_was" ]]; then peel_by+=(precmd); fi
            fi
            print -rn -- $'\\0Peel\\0'"$PROMPT"; for peel_f in $peel_by; do print -rn -- $'\\0'"$peel_f"; done
            print -rn -- $'\\0End\\0'
            """
        let answer = await Subprocess.run("/bin/zsh", ["-l", "-i", "-c", script], environment: environment, timeout: 10)
        guard case .success(let output) = answer, output.status == 0 else { return nil }
        let fields = output.standardOutput.split(separator: 0, omittingEmptySubsequences: false)
        guard let end = fields.lastIndex(of: Data("End".utf8)), let start = fields[..<end].lastIndex(of: Data("Peel".utf8)),
              start + 1 < end
        else { return nil }
        let texts = fields[(start + 1)..<end].map { String(decoding: $0, as: UTF8.self) }
        return ShownPrompt(prompt: texts[0], setBeforeEachCommandBy: Array(texts.dropFirst()))
    }

    public var name: String {
        switch self {
        case .zsh: "zsh"
        case .bash: "bash"
        }
    }

    public var turnOff: String {
        switch self {
        case .zsh: "SHELL_SESSIONS_DISABLE=1"
        case .bash: "touch ~/.bash_sessions_disable"
        }
    }

    public var script: String {
        "/etc/\(name)rc_Apple_Terminal"
    }

    static func loginShell(of user: uid_t = getuid()) -> String? {
        var capacity = 1_024
        while capacity <= 65_536 {
            var entry = passwd()
            var found: UnsafeMutablePointer<passwd>?
            var buffer = [CChar](repeating: 0, count: capacity)
            let (result, shell) = buffer.withUnsafeMutableBufferPointer { bytes -> (Int32, String?) in
                let result = getpwuid_r(user, &entry, bytes.baseAddress, bytes.count, &found)
                guard result == 0, found != nil, let shell = entry.pw_shell else { return (result, nil) }
                return (result, String(cString: shell))
            }
            if result == 0 { return shell }
            guard result == ERANGE else { return nil }
            capacity *= 4
        }
        return nil
    }
}
