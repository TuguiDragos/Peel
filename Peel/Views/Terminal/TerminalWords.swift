import Foundation
import PeelCore

extension ShellSetting.Group {
    var title: LocalizedStringResource {
        switch self {
        case .history: "History"
        case .typing: "Typing"
        case .folders: "Folders"
        case .completion: "Completion"
        case .colors: "Colors"
        }
    }
}

extension ShellSetting {
    var title: LocalizedStringResource {
        switch self {
        case .longHistory: "Remember 50,000 commands"
        case .sharedHistory: "Share history between windows"
        case .timedHistory: "Save when each command ran"
        case .noRepeats: "Skip repeated commands"
        case .spaceHides: "Leave out commands that start with a space"
        case .tidyHistory: "Remove extra spaces"
        case .verifyRecall: "Check recalled commands first"
        case .lockedHistory: "Lock the history file safely"
        case .comments: "Allow comments in commands"
        case .prefixSearch: "Search history with the arrow keys"
        case .pathWords: "Delete paths one folder at a time"
        case .autoCD: "Go to a folder by typing its name"
        case .folderStack: "Remember the folders you visit"
        case .completionMenu: "Choose completions from a menu"
        case .anyCase: "Complete names in any case"
        case .colorfulLs: "Show colors in ls"
        }
    }

    var detail: LocalizedStringResource {
        switch self {
        case .longHistory: "zsh keeps your last 50,000 commands and saves all of them, instead of keeping 2,000 and saving 1,000 as macOS sets it."
        case .sharedHistory: "Each window adds its commands to the history as they run and reads the others’, so the Up Arrow finds them in every window."
        case .timedHistory: "Each command is saved with the time it started and how long it ran, which `history -iD` shows."
        case .noRepeats: "When you run a command that is already in the history, the older copy goes, so each command appears once."
        case .spaceHides: "A command typed after a space isn’t saved, which keeps a password or token you type out of the history."
        case .tidyHistory: "Spaces a command doesn’t need are taken out before it is saved."
        case .verifyRecall: "`!!` and the other history shortcuts put the command on the line for you to check, instead of running it at once."
        case .lockedHistory: "Saving the history locks the file the system’s way, so windows that save at the same time don’t damage it."
        case .comments: "Anything after # on the command line is a comment, as in a script, so a pasted command with comments runs."
        case .prefixSearch: "Type the start of a command, and the Up Arrow and Down Arrow go only through the commands that start that way."
        case .pathWords: "Deleting a word back stops at each slash, so a path goes one folder at a time."
        case .autoCD: "Typing only a folder’s name goes to it, as `cd` does."
        case .folderStack: "The folders you leave are remembered, each only once: `dirs -v` lists them, and `cd +1`, `cd +2`, and so on go back."
        case .completionMenu: "When Tab finds several completions, it opens a menu you move through with the arrow keys."
        case .anyCase: "Tab completes a name whatever its case, so `doc` completes to Documents."
        case .colorfulLs: "`ls` shows folders, links, and programs in the Terminal theme’s colors."
        }
    }
}

extension PromptStyle {
    var title: LocalizedStringResource {
        switch self {
        case .macOS: "macOS"
        case .arrow: "Arrow"
        case .arrowAndBranch: "Arrow and Branch"
        case .twoLines: "Two Lines"
        case .folderOnly: "Folder Only"
        case .classic: "Classic"
        }
    }

    var detail: LocalizedStringResource {
        switch self {
        case .macOS: "The prompt macOS sets: your name, the computer, and the folder you’re in."
        case .arrow: "The folder you’re in, then an arrow that turns red after a command fails."
        case .arrowAndBranch: "The folder and, in a Git repository, its branch, then the arrow."
        case .twoLines: "The folder and branch on one line and the arrow on the next, so the command always has the whole line."
        case .folderOnly: "Only the name of the folder you’re in, then the arrow."
        case .classic: "Your name, the computer, and the folder, in color."
        }
    }
}

extension GitSetting.Group {
    var title: LocalizedStringResource {
        switch self {
        case .pullAndPush: "Pull and Push"
        case .diffsAndMerges: "Diffs and Merges"
        case .branches: "Branches"
        case .signing: "Signing"
        }
    }
}

extension GitSetting {
    var title: LocalizedStringResource {
        switch self {
        case .rebaseOnPull: "Rebase when pulling"
        case .pushNewBranches: "Push new branches without setting them up"
        case .pruneOnFetch: "Remove branches deleted on the remote"
        case .stashBeforeRebase: "Stash changes before a rebase"
        case .histogramDiff: "Use the histogram diff"
        case .colorMovedLines: "Color moved lines"
        case .zdiff3Conflicts: "Show the original in conflicts"
        case .reuseResolutions: "Reuse conflict resolutions"
        case .mainBranch: "Start new repositories on main"
        case .branchesByDate: "List branches by latest commit"
        case .columns: "Show lists in columns"
        case .signCommits: "Sign commits with your SSH key"
        }
    }

    var detail: LocalizedStringResource {
        switch self {
        case .rebaseOnPull: "`git pull` puts your commits after what it fetched, instead of adding a merge commit."
        case .pushNewBranches: "`git push` on a new branch creates it on the remote and follows it, without --set-upstream."
        case .pruneOnFetch: "`git fetch` removes its copies of the branches deleted on the remote, and your own branches stay."
        case .stashBeforeRebase: "A rebase puts uncommitted changes aside and brings them back when it ends."
        case .histogramDiff: "Diffs first match the lines that appear rarely, so changes line up around them."
        case .colorMovedLines: "Lines that moved without changing get colors of their own in a diff."
        case .zdiff3Conflicts: "A conflict shows the lines as they were before both changes, between the two sides."
        case .reuseResolutions: "Git remembers how you resolved a conflict and resolves the same conflict the same way next time."
        case .mainBranch: "`git init` names the first branch main."
        case .branchesByDate: "`git branch` lists the branches with the most recent commit first."
        case .columns: "Commands such as `git branch` and `git tag` show their lists in columns when the window has room."
        case .signCommits: "Every commit is signed with your SSH key, and GitHub shows it as Verified once you add the key there as a signing key."
        }
    }
}

extension SSHSetting {
    var title: LocalizedStringResource {
        switch self {
        case .keychain: "Keep key passphrases in your keychain"
        case .keepAlive: "Keep connections alive"
        case .reuseConnections: "Reuse connections to a server"
        }
    }

    var detail: LocalizedStringResource {
        switch self {
        case .keychain: "ssh asks for a key’s passphrase once, saves it in your keychain, and adds the key to the agent."
        case .keepAlive: "On a quiet connection, ssh checks on the server every minute, so a router doesn’t drop it."
        case .reuseConnections: "A new connection to a server you’re already connected to opens at once through the first, which stays open 10 minutes after the last one ends."
        }
    }
}

extension TerminalTool.Group {
    var title: LocalizedStringResource {
        switch self {
        case .shell: "For the Shell"
        case .git: "For Git"
        case .everyday: "For Every Day"
        }
    }
}

extension TerminalTool {
    var summary: LocalizedStringResource {
        switch self {
        case .zshCompletions: "Completions for many more commands."
        case .fzfTab: "Tab completion in fzf, where typing narrows the list."
        case .zoxide: "Goes to a folder you use from part of its name."
        case .fzf: "Searches your history and files as you type."
        case .direnv: "Sets a project’s environment variables in its folder."
        case .zshAutosuggestions: "Suggests the rest of a command from your history."
        case .zshSyntaxHighlighting: "Colors commands as you type them."
        case .delta: "Diffs with syntax highlighting and line numbers."
        case .gitLFS: "Works with repositories that keep large files in LFS."
        case .lazygit: "A full Git interface inside Terminal."
        case .bat: "Shows files with syntax highlighting, and colors manual pages."
        case .hyperfine: "Measures how long commands take."
        case .tlrc: "Short, practical examples for a command."
        }
    }

    var detail: LocalizedStringResource {
        switch self {
        case .zshCompletions: "Adds completions for many commands zsh doesn’t complete on its own. If zsh then warns about insecure folders, `brew info zsh-completions` says how to fix it."
        case .fzfTab: "Tab shows its completions in fzf, where typing narrows them. Its lines go after the completion system starts and before zsh-autosuggestions."
        case .zoxide: "Remembers the folders you use: `z` with part of a name goes to the best match, and `zi` lets you choose."
        case .fzf: "Control-R searches your history, Control-T pastes files and folders, and Option-C, with Option as Meta, goes to a folder. With --color=16, it uses the Terminal theme’s colors."
        case .direnv: "Loads and unloads environment variables as you enter and leave a project’s folder, from its .envrc file once you allow it with `direnv allow`."
        case .zshAutosuggestions: "Shows the rest of a command in gray as you type, from your history, and the Right Arrow accepts it."
        case .zshSyntaxHighlighting: "Colors the command line as you type, so a command that doesn’t exist shows before you press Return. Its line must be the last in ~/.zshrc."
        case .delta: "Shows `git diff`, `git log`, and `git show` with syntax highlighting and line numbers. With BAT_THEME set to ansi, it uses the Terminal theme’s colors."
        case .gitLFS: "Lets Git clone and work with repositories that keep large files in Git LFS. `git lfs install` sets it up once for your account."
        case .lazygit: "Stage, commit, branch, rebase, and resolve conflicts from a full interface in Terminal. Run `lazygit` in a repository."
        case .bat: "Prints files with syntax highlighting, line numbers, and Git changes. BAT_THEME=ansi uses the Terminal theme’s colors, and MANPAGER shows manual pages through it."
        case .hyperfine: "Runs a command many times and reports how long it takes, such as `hyperfine \"zsh -i -c exit\"` for how long a new shell takes to start."
        case .tlrc: "`tldr` followed by a command shows short, practical examples of it, from the tldr pages."
        }
    }
}

extension TerminalTool.Place {
    var caption: LocalizedStringResource {
        switch self {
        case .zshrc: "Then add to ~/.zshrc"
        case .lastLineOfZshrc: "Then add as the last line of ~/.zshrc"
        case .terminal: "Then run in Terminal"
        }
    }
}
