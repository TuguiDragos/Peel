public import Foundation

/// A tool the Tools tab offers to install with Homebrew, with what its own documentation says to do after. Peel
/// installs nothing: it shows the commands and lines to copy. The shell's tools are listed in the order their lines
/// load in `~/.zshrc`, which is the order they need.
public enum TerminalTool: CaseIterable, Sendable {
    case zshCompletions
    case fzfTab
    case zoxide
    case fzf
    case direnv
    case zshAutosuggestions
    case zshSyntaxHighlighting
    case delta
    case gitLFS
    case lazygit
    case bat
    case hyperfine
    case tlrc

    public enum Group: CaseIterable, Sendable {
        case shell, git, everyday
    }

    public enum Place: Sendable {
        case zshrc
        case lastLineOfZshrc
        case terminal
    }

    public struct Setup: Equatable, Sendable {
        public let place: Place
        public let lines: [String]
    }

    public enum Availability: Equatable, Sendable {
        case available
        case retired(HomebrewRetirement)
        case unknownToHomebrew
    }

    public var group: Group {
        switch self {
        case .zshCompletions, .fzfTab, .zoxide, .fzf, .direnv, .zshAutosuggestions, .zshSyntaxHighlighting: .shell
        case .delta, .gitLFS, .lazygit: .git
        case .bat, .hyperfine, .tlrc: .everyday
        }
    }

    public var formula: String {
        switch self {
        case .zshCompletions: "zsh-completions"
        case .fzfTab: "fzf-tab"
        case .zoxide: "zoxide"
        case .fzf: "fzf"
        case .direnv: "direnv"
        case .zshAutosuggestions: "zsh-autosuggestions"
        case .zshSyntaxHighlighting: "zsh-syntax-highlighting"
        case .delta: "git-delta"
        case .gitLFS: "git-lfs"
        case .lazygit: "lazygit"
        case .bat: "bat"
        case .hyperfine: "hyperfine"
        case .tlrc: "tlrc"
        }
    }

    public var name: String {
        switch self {
        case .delta: "delta"
        case .gitLFS: "Git LFS"
        default: formula
        }
    }

    public var project: URL {
        let address = switch self {
        case .zshCompletions: "https://github.com/zsh-users/zsh-completions"
        case .fzfTab: "https://github.com/Aloxaf/fzf-tab"
        case .zoxide: "https://github.com/ajeetdsouza/zoxide"
        case .fzf: "https://github.com/junegunn/fzf"
        case .direnv: "https://github.com/direnv/direnv"
        case .zshAutosuggestions: "https://github.com/zsh-users/zsh-autosuggestions"
        case .zshSyntaxHighlighting: "https://github.com/zsh-users/zsh-syntax-highlighting"
        case .delta: "https://github.com/dandavison/delta"
        case .gitLFS: "https://github.com/git-lfs/git-lfs"
        case .lazygit: "https://github.com/jesseduffield/lazygit"
        case .bat: "https://github.com/sharkdp/bat"
        case .hyperfine: "https://github.com/sharkdp/hyperfine"
        case .tlrc: "https://github.com/tldr-pages/tlrc"
        }
        return URL(string: address)!
    }

    /// fzf-tab runs fzf, which Homebrew does not install with it.
    public var formulae: [String] {
        self == .fzfTab ? ["fzf", formula] : [formula]
    }

    public var installCommand: String {
        "brew install " + formulae.joined(separator: " ")
    }

    public func setup(prefix: URL) -> [Setup] {
        let path = { (below: String) in prefix.appending(path: below).path(percentEncoded: false) }
        return switch self {
        case .zshCompletions: [Setup(place: .zshrc, lines: ["FPATH=\"\(path("share/zsh-completions")):$FPATH\"", "autoload -Uz compinit && compinit"])]
        case .fzfTab: [Setup(place: .zshrc, lines: ["source \"\(path("opt/fzf-tab/share/fzf-tab/fzf-tab.zsh"))\"", "zstyle ':completion:*' menu no"])]
        case .zoxide: [Setup(place: .zshrc, lines: ["eval \"$(zoxide init zsh)\""])]
        case .fzf: [Setup(place: .zshrc, lines: ["source <(fzf --zsh)", "export FZF_DEFAULT_OPTS=\"$FZF_DEFAULT_OPTS --color=16\""])]
        case .direnv: [Setup(place: .zshrc, lines: ["eval \"$(direnv hook zsh)\""])]
        case .zshAutosuggestions: [Setup(place: .zshrc, lines: ["source \"\(path("share/zsh-autosuggestions/zsh-autosuggestions.zsh"))\""])]
        case .zshSyntaxHighlighting:
            [Setup(place: .lastLineOfZshrc, lines: ["source \"\(path("share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"))\""])]
        case .delta:
            [Setup(place: .terminal, lines: [
                "git config --global core.pager delta",
                "git config --global interactive.diffFilter 'delta --color-only'",
                "git config --global delta.navigate true",
            ])]
        case .gitLFS: [Setup(place: .terminal, lines: ["git lfs install"])]
        // macOS's man marks bold text with backspaces, which bat would show as they are, so col -bx removes them first.
        case .bat: [Setup(place: .zshrc, lines: ["export BAT_THEME=ansi", "export MANPAGER=\"sh -c 'col -bx | bat -l man -p'\""])]
        case .lazygit, .hyperfine, .tlrc: []
        }
    }

    public func isInstalled(prefix: URL) -> Bool {
        formulae.allSatisfy {
            FileManager.default.fileExists(atPath: prefix.appending(path: "opt/\($0)").path(percentEncoded: false))
        }
    }

    /// Whether Homebrew still offers the tool: `known` is every formula name it knows, and `packages` what it said
    /// of the tool's formulae, which carries a retirement and the formula that replaces it.
    public func availability(known: Set<String>, packages: [HomebrewPackage]) -> Availability {
        guard formulae.allSatisfy(known.contains) else { return .unknownToHomebrew }
        let retirement = packages.first { formulae.contains($0.name) && $0.retirement != nil }?.retirement
        return retirement.map(Availability.retired) ?? .available
    }
}
