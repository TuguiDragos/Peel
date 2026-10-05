import Darwin

/// The zsh prompt Peel writes, built from what comes before the symbol, the Git branch, the symbol, and how they show.
public struct Prompt: Hashable, Sendable {
    public enum Start: CaseIterable, Sendable {
        case folder
        case path
        case nameAndFolder
    }

    /// Characters Unicode gives one column everywhere (neutral or narrow in UAX #11), so Terminal never draws one over
    /// the command, whatever its setting for ambiguous widths.
    public enum Symbol: String, CaseIterable, Sendable {
        case chevron = "❯"
        case arrow = "➜"
        case angle = "›"
        case triangle = "▸"
        case guillemet = "»"
        case dollar = "$"
        case percent = "%"
        case greaterThan = ">"
    }

    /// A run of the prompt's text in one of the 16 colors a Terminal theme sets, or in its text color when nil.
    public struct Segment: Equatable, Sendable {
        public let text: String
        public let color: Int?

        public init(_ text: String, _ color: Int? = nil) {
            self.text = text
            self.color = color
        }
    }

    public var start: Start
    public var showsBranch: Bool
    public var symbol: Symbol
    public var turnsRedAfterAFailure: Bool
    public var isOnItsOwnLine: Bool

    public init(
        start: Start = .folder,
        showsBranch: Bool = true,
        symbol: Symbol = .chevron,
        turnsRedAfterAFailure: Bool = true,
        isOnItsOwnLine: Bool = false
    ) {
        self.start = start
        self.showsBranch = showsBranch
        self.symbol = symbol
        self.turnsRedAfterAFailure = turnsRedAfterAFailure
        self.isOnItsOwnLine = isOnItsOwnLine
    }

    public static let all: [Prompt] = Start.allCases.flatMap { start in
        [true, false].flatMap { showsBranch in
            Symbol.allCases.flatMap { symbol in
                [true, false].flatMap { turnsRed in
                    [false, true].map { isOnItsOwnLine in
                        Prompt(
                            start: start,
                            showsBranch: showsBranch,
                            symbol: symbol,
                            turnsRedAfterAFailure: turnsRed,
                            isOnItsOwnLine: isOnItsOwnLine
                        )
                    }
                }
            }
        }
    }

    public static let branchLines = [
        "autoload -Uz vcs_info add-zsh-hook",
        "zstyle ':vcs_info:*' enable git",
        "zstyle ':vcs_info:git:*' formats ' %F{yellow}%b%f'",
        "zstyle ':vcs_info:git:*' actionformats ' %F{yellow}%b%f %F{red}%a%f'",
        "add-zsh-hook precmd vcs_info",
        "setopt PROMPT_SUBST",
    ]

    public var lines: [String] {
        let before = switch start {
        case .folder: "%F{cyan}%1~%f"
        case .path: "%F{cyan}%~%f"
        case .nameAndFolder: "%F{green}%n@%m%f %F{cyan}%1~%f"
        }
        let branch = showsBranch ? "${vcs_info_msg_0_}" : ""
        let mark = symbol == .percent ? "%%" : symbol.rawValue
        let symbol = turnsRedAfterAFailure ? "%(?.%F{green}.%F{red})\(mark)%f" : "%F{green}\(mark)%f"
        let prompt = isOnItsOwnLine
            ? "PROMPT=$'\(before)\(branch)\\n\(symbol) '"
            : "PROMPT='\(before)\(branch) \(symbol) '"
        return (showsBranch ? Self.branchLines : []) + [prompt]
    }

    /// How the prompt reads in `path`, written from the home folder as `~/…`, after a command that `failed` or not.
    public func sample(user: String, host: String, path: String, branch: String?, failed: Bool) -> [Segment] {
        let folder = path == "~" ? path : String(path.split(separator: "/").last ?? "")
        var segments = switch start {
        case .folder: [Segment(folder, 6)]
        case .path: [Segment(path, 6)]
        case .nameAndFolder: [Segment("\(user)@\(host)", 2), Segment(" "), Segment(folder, 6)]
        }
        if showsBranch, let branch {
            segments += [Segment(" "), Segment(branch, 3)]
        }
        segments.append(Segment(isOnItsOwnLine ? "\n" : " "))
        segments.append(Segment(symbol.rawValue, turnsRedAfterAFailure && failed ? 1 : 2))
        segments.append(Segment(" "))
        return segments
    }

    /// The computer's name as zsh's `%m` shows it: up to the first dot.
    public static func hostName() -> String {
        var name = [CChar](repeating: 0, count: Int(MAXHOSTNAMELEN) + 1)
        guard gethostname(&name, name.count - 1) == 0 else { return "" }
        let bytes = name.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes.prefix { $0 != UInt8(ascii: ".") }, as: UTF8.self)
    }
}
