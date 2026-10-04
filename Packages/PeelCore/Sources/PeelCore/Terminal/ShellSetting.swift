public enum ShellSetting: CaseIterable, Sendable {
    case longHistory
    case sharedHistory
    case timedHistory
    case noRepeats
    case spaceHides
    case tidyHistory
    case verifyRecall
    case lockedHistory
    case comments
    case prefixSearch
    case pathWords
    case autoCD
    case folderStack
    case completionMenu
    case anyCase
    case colorfulLs

    public enum Group: CaseIterable, Sendable {
        case history, typing, folders, completion, colors
    }

    public var group: Group {
        switch self {
        case .longHistory, .sharedHistory, .timedHistory, .noRepeats, .spaceHides, .tidyHistory, .verifyRecall,
             .lockedHistory: .history
        case .comments, .prefixSearch, .pathWords: .typing
        case .autoCD, .folderStack: .folders
        case .completionMenu, .anyCase: .completion
        case .colorfulLs: .colors
        }
    }

    public var lines: [String] {
        switch self {
        case .longHistory: ["HISTSIZE=50000", "SAVEHIST=50000"]
        case .sharedHistory: ["setopt SHARE_HISTORY"]
        case .timedHistory: ["setopt EXTENDED_HISTORY"]
        case .noRepeats: ["setopt HIST_IGNORE_ALL_DUPS"]
        case .spaceHides: ["setopt HIST_IGNORE_SPACE"]
        case .tidyHistory: ["setopt HIST_REDUCE_BLANKS"]
        case .verifyRecall: ["setopt HIST_VERIFY"]
        case .lockedHistory: ["setopt HIST_FCNTL_LOCK"]
        case .comments: ["setopt INTERACTIVE_COMMENTS"]
        case .prefixSearch:
            [
                "autoload -Uz up-line-or-beginning-search down-line-or-beginning-search",
                "zle -N up-line-or-beginning-search",
                "zle -N down-line-or-beginning-search",
                "bindkey '^[[A' up-line-or-beginning-search",
                "bindkey '^[OA' up-line-or-beginning-search",
                "bindkey '^[[B' down-line-or-beginning-search",
                "bindkey '^[OB' down-line-or-beginning-search",
            ]
        case .pathWords: ["WORDCHARS=${WORDCHARS//[\\/]}"]
        case .autoCD: ["setopt AUTO_CD"]
        case .folderStack: ["setopt AUTO_PUSHD PUSHD_IGNORE_DUPS"]
        case .completionMenu: ["zstyle ':completion:*' menu select"]
        case .anyCase: ["zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'"]
        case .colorfulLs: ["export CLICOLOR=1"]
        }
    }
}
