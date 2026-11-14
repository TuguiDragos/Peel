import Foundation
internal import PeelPrivileged

/// What in a job's command is worth a second look, read from the command's shape and never from a name. It claims
/// nothing about the job: software installed on purpose can do any of these.
public enum UnusualCommand: String, Sendable, Hashable {
    /// The program sits in a temporary folder: one any process on the Mac can write to, or an account's own.
    case runsFromATemporaryFolder
    /// The program sits in `/Users/Shared`, which every account on the Mac can write to.
    case runsFromTheSharedFolder
    /// The program is `curl` or `wget`, which reach a network address.
    case downloads
    /// The command decodes base64, a way to carry a script that can't be read at a glance.
    case decodesBase64
    /// A shell or an interpreter runs code written into the job's own file, given to the option it takes code in.
    case runsCodeFromItsSettings

    private static let temporaryFolders = ["/tmp", "/private/tmp", "/var/tmp", "/private/var/tmp"]
    /// Where macOS keeps each account's folders, its temporary one being `<two names>/T` inside.
    private static let accountFolders = ["/var/folders", "/private/var/folders"]
    private static let decodingFlags: Set = ["-d", "-D", "--decode"]
    private static let downloaders: Set = ["curl", "wget"]
    /// How an interpreter reads the options before its script, as its manual page gives them: which take code, and
    /// which take a value, a word that is neither the script nor an option.
    private struct Options {
        var code: Set<Character>
        var longCode: Set<String> = []
        /// Their value is the rest of the word or, with nothing after the letter, the next word.
        var valued: Set<Character> = []
        /// Their value is the next word, and the letters after them in the word go on being options.
        var valuedByNextWord: Set<Character> = []
        /// Their value, when they have one, is the rest of the word, never the next word.
        var valuedInPlace: Set<Character> = []
        var longValued: Set<String> = []
        /// No word after theirs is an option.
        var last: Set<Character> = []
        /// A word that starts with `+` holds options too.
        var takesPlus = false
    }

    /// From `bash(1)`, `dash(1)`, `ksh(1)`, `zsh(1)`, `tcsh(1)`, `perlrun(1)`, `ruby(1)`, `osascript(1)`, `node(1)`,
    /// Python's and fish's own pages on their command line, and PHP's Command line options.
    private static let options: [String: Options] = {
        let bash = Options(
            code: ["c"], valuedByNextWord: ["o", "O"], longValued: ["--rcfile", "--init-file"], takesPlus: true
        )
        let csh = Options(code: ["c"], valuedInPlace: ["D"], last: ["b"])
        let python = Options(
            code: ["c"], valued: ["W", "X", "m"], longValued: ["--check-hash-based-pycs"], last: ["m"]
        )
        return [
            "sh": bash, "bash": bash,
            "dash": Options(code: ["c"], valuedByNextWord: ["o"], takesPlus: true),
            "ksh": Options(code: ["c"], valued: ["o", "R"], takesPlus: true),
            "zsh": Options(
                code: ["c"], valued: ["o"], valuedInPlace: ["-"], longValued: ["--emulate"], last: ["b", "-"],
                takesPlus: true
            ),
            "csh": csh, "tcsh": csh,
            "fish": Options(
                code: ["c", "C"], longCode: ["--command", "--init-command"], valued: ["d", "o", "p", "f"],
                longValued: ["--debug", "--debug-output", "--profile", "--profile-startup", "--features"]
            ),
            "python": python, "python3": python,
            "perl": Options(
                code: ["e", "E"], valued: ["I"], valuedInPlace: ["M", "m", "F", "x", "C", "i", "D", ":"]
            ),
            "ruby": Options(
                code: ["e"], valued: ["I", "r", "C", "X", "E"], valuedInPlace: ["W", "F", "K", "x", "T", "i"],
                longValued: ["--encoding"]
            ),
            "osascript": Options(code: ["e"], valued: ["l", "s"]),
            "node": Options(
                code: ["e", "p"], longCode: ["--eval", "--print"], valued: ["r", "C"],
                longValued: [
                    "--require", "--import", "--loader", "--experimental-loader", "--conditions", "--title",
                    "--input-type", "--env-file",
                ]
            ),
            "php": Options(
                code: ["r", "B", "R", "E"], longCode: ["--run", "--process-begin", "--process-code", "--process-end"],
                valued: ["d", "c", "f", "F", "S", "t"],
                longValued: ["--define", "--php-ini", "--file", "--process-file", "--server", "--docroot"]
            ),
        ]
    }()

    /// `arguments` are the program and its arguments, as launchd runs them. What a launcher such as `env` or `nohup`
    /// runs is judged, and so is where the script an interpreter runs from disk is.
    init?(arguments: [String]) {
        let arguments = Self.withoutLauncher(arguments)
        guard let program = arguments.first else { return nil }
        let name = (program as NSString).lastPathComponent
        let given = Self.given(arguments, as: name)
        let runs = [program] + [given.script].compactMap(\.self)
        if runs.contains(where: Self.isTemporary) {
            self = .runsFromATemporaryFolder
        } else if runs.contains(where: { PathComponents.isPath($0, inside: "/Users/Shared") }) {
            self = .runsFromTheSharedFolder
        } else if Self.downloaders.contains(name) {
            self = .downloads
        } else if Self.decodesBase64(arguments) {
            self = .decodesBase64
        } else if given.code {
            self = .runsCodeFromItsSettings
        } else {
            return nil
        }
    }

    /// The command `env` or `nohup` runs (`man env`, `man nohup`): past `env`'s options, `-C`, `-P` and `-u` with their
    /// value, and then its `NAME=value` settings. `env -S`, which splits a string into the command, is left as it is.
    private static func withoutLauncher(_ arguments: [String]) -> [String] {
        guard let first = arguments.first else { return arguments }
        var rest = Array(arguments.dropFirst())
        switch (first as NSString).lastPathComponent {
        case "nohup":
            if rest.first == "--" { rest.removeFirst() }
        case "env":
            options: while let argument = rest.first, argument.hasPrefix("-") {
                rest.removeFirst()
                if argument == "--" { break }
                var letters = argument.dropFirst()
                while let letter = letters.popFirst() {
                    if letter == "S" { return arguments }
                    if "CPu".contains(letter) {
                        if letters.isEmpty, !rest.isEmpty { rest.removeFirst() }
                        continue options
                    }
                }
            }
            while rest.first?.contains("=") == true { rest.removeFirst() }
        default:
            return arguments
        }
        return rest.isEmpty ? arguments : withoutLauncher(rest)
    }

    /// What an interpreter named `name` is given to run: code in one of its options, among the options before the first
    /// argument that is none, or that argument, the script it runs from disk, everything after it being the script's
    /// own. A long option not listed is taken to have no value: the search can then stop at its value and miss the
    /// code, but never reads a script's own option as the interpreter's.
    private static func given(_ arguments: [String], as name: String) -> (code: Bool, script: String?) {
        guard let options = options[name] else { return (false, nil) }
        var isAValue = false
        var arguments = arguments.dropFirst()
        while let argument = arguments.popFirst() {
            if isAValue {
                isAValue = false
                continue
            }
            if ["--", "+-"].contains(argument) { return (false, arguments.first) }
            let holdsOptions = argument.hasPrefix("-") || options.takesPlus && argument.hasPrefix("+")
            guard holdsOptions else { return (false, argument) }
            guard !["-", "+"].contains(argument) else { return (false, nil) }
            if argument.hasPrefix("--") || argument.hasPrefix("+-") {
                let option = String(argument.prefix { $0 != "=" })
                if options.longCode.contains(option) { return (true, nil) }
                isAValue = option == argument && options.longValued.contains(option)
                continue
            }
            var isLast = false
            var letters = argument.dropFirst()
            while let letter = letters.popFirst() {
                if options.code.contains(letter) { return (true, nil) }
                if options.last.contains(letter) { isLast = true }
                if options.valued.contains(letter) {
                    isAValue = letters.isEmpty
                    break
                }
                if options.valuedByNextWord.contains(letter) { isAValue = true }
                if options.valuedInPlace.contains(letter) { break }
            }
            if isLast { return (false, nil) }
        }
        return (false, nil)
    }

    private static func isTemporary(_ program: String) -> Bool {
        if temporaryFolders.contains(where: { PathComponents.isPath(program, inside: $0) }) { return true }
        return accountFolders.contains { folder in
            guard PathComponents.isPath(program, inside: folder) else { return false }
            let below = PathComponents.of(program).dropFirst(PathComponents.of(folder).count)
            return below.count > 3 && below.dropFirst(2).first == "T"
        }
    }

    /// Whether the command runs `base64` to decode: the program, as a word of any argument, and a decoding flag after
    /// it. A file or an option merely named so says nothing.
    private static func decodesBase64(_ arguments: [String]) -> Bool {
        let words = arguments.flatMap { $0.split { " \t\n|;&()".contains($0) }.map(String.init) }
        guard let index = words.firstIndex(where: { ($0 as NSString).lastPathComponent == "base64" }) else {
            return false
        }
        return words[(index + 1)...].contains(where: decodingFlags.contains)
    }
}
