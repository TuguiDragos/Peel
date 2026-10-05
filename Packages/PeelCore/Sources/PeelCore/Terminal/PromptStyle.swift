import Darwin

public enum PromptStyle: CaseIterable, Sendable {
    case macOS
    case arrow
    case arrowAndBranch
    case twoLines
    case folderOnly
    case classic

    /// A run of the prompt's text in one of the 16 colors a Terminal theme sets, or in its text color when nil.
    public struct Segment: Equatable, Sendable {
        public let text: String
        public let color: Int?

        public init(_ text: String, _ color: Int? = nil) {
            self.text = text
            self.color = color
        }
    }

    static let branchLines = [
        "autoload -Uz vcs_info add-zsh-hook",
        "zstyle ':vcs_info:*' enable git",
        "zstyle ':vcs_info:git:*' formats ' %F{yellow}%b%f'",
        "zstyle ':vcs_info:git:*' actionformats ' %F{yellow}%b%f %F{red}%a%f'",
        "add-zsh-hook precmd vcs_info",
        "setopt PROMPT_SUBST",
    ]

    public var lines: [String] {
        switch self {
        case .macOS: []
        case .arrow: ["PROMPT='%F{cyan}%~%f %(?.%F{green}.%F{red})❯%f '"]
        case .arrowAndBranch: Self.branchLines + ["PROMPT='%F{cyan}%~%f${vcs_info_msg_0_} %(?.%F{green}.%F{red})❯%f '"]
        case .twoLines: Self.branchLines + ["PROMPT=$'%F{cyan}%~%f${vcs_info_msg_0_}\\n%(?.%F{green}.%F{red})❯%f '"]
        case .folderOnly: ["PROMPT='%F{cyan}%1~%f %(?.%F{green}.%F{red})❯%f '"]
        case .classic: ["PROMPT='%F{green}%n@%m%f %F{blue}%~%f %# '"]
        }
    }

    /// How the prompt reads in `path`, written from the home folder as `~/…`, after a command that `failed` or not.
    public func sample(user: String, host: String, path: String, branch: String?, failed: Bool) -> [Segment] {
        let folder = path == "~" ? path : String(path.split(separator: "/").last ?? "")
        let mark = Segment("❯", failed ? 1 : 2)
        let onBranch = branch.map { [Segment(" "), Segment($0, 3)] } ?? []
        switch self {
        case .macOS: return [Segment("\(user)@\(host) \(folder) % ")]
        case .arrow: return [Segment(path, 6), Segment(" "), mark, Segment(" ")]
        case .arrowAndBranch: return [Segment(path, 6)] + onBranch + [Segment(" "), mark, Segment(" ")]
        case .twoLines: return [Segment(path, 6)] + onBranch + [Segment("\n"), mark, Segment(" ")]
        case .folderOnly: return [Segment(folder, 6), Segment(" "), mark, Segment(" ")]
        case .classic: return [Segment("\(user)@\(host)", 2), Segment(" "), Segment(path, 4), Segment(" % ")]
        }
    }

    /// The computer's name as zsh's `%m` shows it: up to the first dot.
    public static func hostName() -> String {
        var name = [CChar](repeating: 0, count: Int(MAXHOSTNAMELEN) + 1)
        guard gethostname(&name, name.count - 1) == 0 else { return "" }
        let bytes = name.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes.prefix { $0 != UInt8(ascii: ".") }, as: UTF8.self)
    }
}
