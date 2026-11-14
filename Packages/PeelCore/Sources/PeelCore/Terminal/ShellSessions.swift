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

    /// The ZDOTDIR of the session Peel runs in, which Terminal's zsh starts with too, since launchd starts both. A Peel
    /// started from a shell has that shell's instead.
    static var sessionZDOTDIR: String? {
        sessionZDOTDIR(parent: getppid(), environment: ProcessInfo.processInfo.environment)
    }

    static func sessionZDOTDIR(parent: pid_t, environment: [String: String]) -> String? {
        parent == 1 ? environment["ZDOTDIR"] : nil
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

    /// The `.zshrc` zsh reads, where the line that sources Peel's file goes: in the folder `ZDOTDIR` names before zsh
    /// reads it, since `.zshenv` or `.zprofile` may set it (`man zsh`, STARTUP/SHUTDOWN FILES). zsh is asked as
    /// Terminal starts it, a login shell, on its own since it runs the account's files; nil when it doesn't answer.
    public func zshrc(home: URL = .homeDirectory) async -> URL? {
        await zshrc(home: home, zdotdir: Self.sessionZDOTDIR)
    }

    public func zshrcByTheText(home: URL = .homeDirectory) -> URL? {
        zshrcByTheText(home: home, zdotdir: Self.sessionZDOTDIR)
    }

    /// The `.zshrc` the startup files' text names, or nil when their text gives ZDOTDIR a value it can't settle.
    func zshrcByTheText(home: URL, zdotdir: String?) -> URL? {
        guard case .zsh(let zshenv) = self else { return nil }
        let named = Self.foldersNamedByStartupFiles(from: zshenv, home: home, zdotdir: zdotdir)
        guard named.isSettled else { return nil }
        return named.folders.last?.appending(path: ".zshrc", directoryHint: .notDirectory)
    }

    /// `zdotdir` is set for zsh only when the session sets it, since `.zshenv` may keep a ZDOTDIR it finds
    /// (`${ZDOTDIR:-$HOME/.config/zsh}`).
    func zshrc(home: URL, zdotdir: String?, asking responsibility: Subprocess.Responsibility? = .system) async -> URL? {
        guard case .zsh = self else { return nil }
        var environment = [
            "HOME": home.pathAsHOME,
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
        ]
        if let zdotdir, !zdotdir.isEmpty {
            environment["ZDOTDIR"] = (zdotdir as NSString).standardizingPath
        }
        let answer = await Subprocess.runOnItsOwn(
            "/bin/zsh", ["-l", "-c", #"print -r -- "peel-zdotdir:${ZDOTDIR:-$HOME}""#],
            environment: environment, timeout: 10, asking: responsibility
        )
        // The startup files may print too.
        let marker = "peel-zdotdir:/"
        guard case .success(let output) = answer, output.status == 0,
              let line = output.text.split(separator: "\n").last(where: { $0.hasPrefix(marker) })
        else { return nil }
        return URL(filePath: String(line.dropFirst(marker.count - 1)), directoryHint: .isDirectory)
            .appending(path: ".zshrc", directoryHint: .notDirectory)
    }

    /// What zsh's startup files say of ZDOTDIR, read from their text and never by running them.
    struct NamedFolders: Equatable {
        /// The folder `.zshenv` is in, then each folder a startup file plainly gives ZDOTDIR.
        var folders: [URL]
        /// False when a startup file also gives ZDOTDIR a value its text can't settle: one a shell would have to work
        /// out, or one given under a condition.
        var isSettled = true
        /// The folders such a value may name: given under a condition, or with a variable the text doesn't set or can't
        /// settle, taken from the environment or, for XDG's, its default.
        var candidates: [URL] = []
        /// The folders the text plainly gives other variables, which a later value may name.
        var variables: [String: String] = [:]
        /// The variables the text gives a value it can't settle, so a value that reads one can't be settled either.
        var unsettledVariables: Set<String> = []
    }

    /// The folders zsh may read its startup files from, going by their text alone: the one `zshenv` is in, then each
    /// folder a `.zshenv` or a `.zprofile` there plainly gives ZDOTDIR.
    static func foldersNamedByStartupFiles(from zshenv: URL, home: URL, zdotdir: String?) -> NamedFolders {
        var named = NamedFolders(folders: [zshenv.deletingLastPathComponent()])
        var environment = zdotdir.map { ["ZDOTDIR": $0] } ?? [:]
        for name in [".zshenv", ".zprofile"] {
            for folder in named.folders {
                let file = folder.appending(path: name, directoryHint: .notDirectory)
                guard let data = BoundedRead.data(at: file, maximum: ShellReferences.maximumBytes) else { continue }
                let given = foldersGivenToZDOTDIR(
                    in: String(decoding: data, as: UTF8.self), home: home, environment: environment,
                    unsettled: named.unsettledVariables
                )
                named.folders += given.folders
                named.candidates += given.candidates
                named.isSettled = named.isSettled && given.isSettled
                environment.merge(given.variables) { _, later in later }
                named.unsettledVariables = given.unsettledVariables
            }
        }
        return named
    }

    /// The folders a zsh startup file gives `ZDOTDIR`, read from its text and never by running it. Only an assignment
    /// on a line of its own, outside any block the text opens, with a value written plainly, names a folder: a path,
    /// with `~`, `$HOME`, or `${NAME:-default}`, its parts quoted or not. Any other assignment leaves it unsettled, and
    /// so does a value that reads a variable given a value any other way, in this text or in `unsettled`.
    static func foldersGivenToZDOTDIR(
        in text: String, home: URL, environment: [String: String], unsettled: Set<String> = []
    ) -> NamedFolders {
        var named = NamedFolders(folders: [], unsettledVariables: unsettled)
        var depth = 0
        for line in text.split(whereSeparator: \.isNewline) {
            let code = withoutComment(line.drop(while: \.isWhitespace))
            var words = code[...]
            for prefix in ["export ", "typeset -x ", "typeset -gx "] where words.hasPrefix(prefix) {
                words = words.dropFirst(prefix.count).drop(while: \.isWhitespace)
            }
            let known = environment.merging(named.variables) { _, later in later }
            let given = variablesGivenAValue(by: code)
            var settled: String?
            if given.contains("ZDOTDIR") {
                let value = words.hasPrefix("ZDOTDIR=") ? words.dropFirst("ZDOTDIR=".count) : nil
                if depth == 0, let value, !reads(value, anyOf: named.unsettledVariables),
                   let folder = plainFolder(value, home: home, environment: known) {
                    named.folders.append(folder)
                    settled = "ZDOTDIR"
                } else {
                    named.isSettled = false
                    let defaults = known.merging(xdgDefaults(home: home)) { set, _ in set }
                    if let value, let folder = plainFolder(value, home: home, environment: defaults) {
                        named.candidates.append(folder)
                    }
                }
            } else if depth == 0, let equals = words.firstIndex(of: "="),
                      words[..<equals].wholeMatch(of: /[A-Za-z_][A-Za-z0-9_]*/) != nil,
                      !reads(words[equals...], anyOf: named.unsettledVariables),
                      let folder = plainFolder(words[words.index(after: equals)...], home: home, environment: known) {
                settled = String(words[..<equals])
                named.variables[String(words[..<equals])] = folder.path(percentEncoded: false)
            }
            named.unsettledVariables.formUnion(given)
            if let settled { named.unsettledVariables.remove(settled) }
            depth = max(0, depth + blocksOpened(by: code))
        }
        return named
    }

    /// The variables a line gives a value: `NAME=`, `NAME+=`, `${NAME=…}`, `${NAME:=…}`, `${NAME::=…}`, or an
    /// `unset`.
    private static func variablesGivenAValue(by code: Substring) -> Set<String> {
        let assignment = /(?:^|[^A-Za-z0-9_])([A-Za-z_][A-Za-z0-9_]*)\+?=|\$\{([A-Za-z_][A-Za-z0-9_]*):{0,2}=/
        var names = Set(code.matches(of: assignment).compactMap { ($0.output.1 ?? $0.output.2).map(String.init) })
        if let unset = code.firstMatch(of: /(?:^|[^A-Za-z0-9_])unset\s/) {
            let unsetNames = code[unset.range.upperBound...].matches(of: /[A-Za-z_][A-Za-z0-9_]*/)
            names.formUnion(unsetNames.map { String($0.output) })
        }
        return names
    }

    /// Whether `value` reads any of `names`, as `$NAME` or `${NAME…}`.
    private static func reads(_ value: Substring, anyOf names: Set<String>) -> Bool {
        guard !names.isEmpty else { return false }
        return value.matches(of: /\$\{?([A-Za-z_][A-Za-z0-9_]*)/).contains { names.contains(String($0.output.1)) }
    }

    /// Where the XDG Base Directory Specification puts each folder that its variable doesn't name.
    private static func xdgDefaults(home: URL) -> [String: String] {
        let homePath = home.pathAsHOME
        return [
            "XDG_CONFIG_HOME": homePath + "/.config", "XDG_DATA_HOME": homePath + "/.local/share",
            "XDG_STATE_HOME": homePath + "/.local/state", "XDG_CACHE_HOME": homePath + "/.cache",
        ]
    }

    /// A line without what follows an unquoted `#` that begins a word, which zsh reads as a comment.
    private static func withoutComment(_ line: Substring) -> Substring {
        var quote: Character?
        var previous: Character = " "
        for index in line.indices {
            let character = line[index]
            if let open = quote {
                if character == open { quote = nil }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == "#", previous.isWhitespace || previous == ";" {
                return line[..<index]
            }
            previous = character
        }
        return line
    }

    /// How many blocks a line opens, less those it closes, counted by the words that open and close them in zsh.
    private static func blocksOpened(by code: Substring) -> Int {
        let words = code.split { $0.isWhitespace || $0 == ";" }
        let opening: Set<Substring> = ["if", "case", "for", "while", "until", "select", "repeat", "{"]
        let closing: Set<Substring> = ["fi", "esac", "done", "}"]
        return words.reduce(0) { count, word in
            if opening.contains(word) || word.hasSuffix("{") && !word.hasPrefix("$") { return count + 1 }
            if closing.contains(word) { return count - 1 }
            return count
        }
    }

    /// The folder a value names, read as zsh reads one word: parts in double quotes, in single quotes, and bare,
    /// written one after the other. Nil when any part holds what a plain path can't.
    private static func plainFolder(_ written: Substring, home: URL, environment: [String: String]) -> URL? {
        let homePath = home.pathAsHOME
        var value = ""
        var rest = written
        var isFirstPart = true
        while let first = rest.first, !first.isWhitespace, first != ";" {
            if first == "\"" || first == "'" {
                let inside = rest.dropFirst()
                guard let end = inside.firstIndex(of: first) else { return nil }
                let part = String(inside[..<end])
                // Nothing inside single quotes stands for anything else.
                guard let expanded = first == "'" ? part : expanding(part, home: homePath, environment: environment)
                else { return nil }
                value += expanded
                rest = inside[inside.index(after: end)...]
            } else {
                var part = String(rest.prefix { !$0.isWhitespace && $0 != ";" && $0 != "\"" && $0 != "'" })
                rest = rest.dropFirst(part.count)
                if isFirstPart, part == "~" || part.hasPrefix("~/") {
                    part = homePath + part.dropFirst()
                }
                guard let expanded = expanding(part, home: homePath, environment: environment) else { return nil }
                value += expanded
            }
            isFirstPart = false
        }
        guard rest.drop(while: \.isWhitespace).allSatisfy({ $0 == ";" || $0.isWhitespace }) else { return nil }
        return absoluteFolder(value)
    }

    /// `part` with `$HOME`, `${HOME}`, and `${NAME:-default}` worked out, or nil when what it names isn't plain.
    private static func expanding(_ part: String, home homePath: String, environment: [String: String]) -> String? {
        var value = part.replacing("${HOME}", with: homePath).replacing(/\$HOME(?![A-Za-z0-9_])/, with: homePath)
        // A variable the text or the environment sets, as `$NAME` or `${NAME}`: zsh doesn't expand its value again.
        while let named = value.firstMatch(of: /\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?/),
              named.output.0.hasPrefix("${") == named.output.0.hasSuffix("}"),
              let set = environment[String(named.output.1)], !set.isEmpty {
            if set.contains(where: notPlain.contains) { return nil }
            value.replaceSubrange(named.range, with: set)
        }
        while let named = value.firstMatch(of: /\$\{([A-Za-z_][A-Za-z0-9_]*):[-=]([^{}]*)\}/) {
            let set = environment[String(named.output.1)].flatMap { $0.isEmpty ? nil : $0 }
            // zsh doesn't expand a value again: one that holds what a plain path can't names no folder, and taken in
            // here it could bring back the form it replaced, for ever.
            if let set, set.contains(where: notPlain.contains) { return nil }
            value.replaceSubrange(named.range, with: set ?? String(named.output.2))
        }
        return value
    }

    private static let notPlain: Set<Character> = ["$", "`", "\\", "(", ")", "{", "}", "*", "?", "["]

    private static func absoluteFolder(_ path: String) -> URL? {
        guard path.hasPrefix("/"), !path.contains(where: notPlain.contains) else { return nil }
        return URL(filePath: (path as NSString).standardizingPath, directoryHint: .isDirectory)
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
    func promptShown(
        home: URL, zdotdir: String?, asking responsibility: Subprocess.Responsibility? = .system
    ) async -> ShownPrompt? {
        guard case .zsh = self else { return nil }
        var environment = [
            "HOME": home.pathAsHOME,
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "TERM": "xterm-256color",
        ]
        if let zdotdir, !zdotdir.isEmpty {
            environment["ZDOTDIR"] = (zdotdir as NSString).standardizingPath
        }
        // An interactive login shell reads `.zlogout` as it exits, and nobody is logging out (`man zshoptions`, RCS).
        let script = """
            setopt no_rcs
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
        let answer = await Subprocess.runOnItsOwn(
            "/bin/zsh", ["-l", "-i", "-c", script], environment: environment, timeout: 10, asking: responsibility
        )
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

    public static func loginShell(of user: uid_t = getuid()) -> String? {
        AccountRecord.field(of: user) { $0.pw_shell }
    }
}
