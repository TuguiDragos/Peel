# Terminal

Peel's Terminal page gives Terminal a theme and sets up the command line around it, on six tabs:

- **Themes**: 29 dark themes, each a Terminal profile built on Apple's own Clear Dark.
- **Terminal**: how Terminal opens, and the theme in use.
- **Shell**, **Git**, and **SSH**: settings zsh, Git, and ssh already have, from their own manuals, each with a switch.
- **Tools**: command-line tools worth having, with the commands that install them and set them up.

<p align="center">
  <img src="Terminal/Renders/Hadal.png" width="49%" alt="The Hadal theme in Terminal">
  <img src="Terminal/Renders/Noctiluca.png" width="49%" alt="The Noctiluca theme in Terminal">
</p>

## Themes

Each theme is a Terminal profile built on Apple's own Clear Dark: the same font and window, with colors of its own,
each checked for contrast against its background.

### With Peel

The Terminal page starts turned off in Peel's sidebar: turn it on in Settings > General > Sidebar, or open it from
the View menu. Choose a theme there, and Terminal opens with it and uses it in every new window, and Put Back gives
Terminal the profile it had before and takes away Peel's own profiles that are still as Peel wrote them. Peel
changes Terminal's profiles, and the one it opens with, only while Terminal is closed, and offers to quit it first.

The Terminal tab of the same page can also leave out the "Last login" line in new windows, keep Terminal from
reopening its windows when it would, make Option the Meta key and silence the bell in the theme you use when it
is one of Peel's, and show the line that stops the shell from saving its sessions, with a Copy button. Peel never
edits your shell's files.

What each writes: leaving out the "Last login" line makes an empty `~/.hushlogin`, the file `login` looks for, and
turning it off moves that file to the Trash; Option as Meta and the bell set `useOptionAsMetaKey` to true and `Bell` to
false in the Peel profile in use; not reopening windows sets Terminal's `NSQuitAlwaysKeepsWindows` to false, at once
even while Terminal is open, since Terminal reads it only when it quits; and the line that stops zsh from saving its
sessions, `SHELL_SESSIONS_DISABLE=1`, goes in `~/.zshenv`, for you to add (for bash, the command is
`touch ~/.bash_sessions_disable`).

### Without Peel

Download a theme below. In Terminal, choose Terminal > Settings, click Profiles, and drag the file into the list of
profiles, or click the Action pop-up menu and choose Import. Select the theme and click Default to open every new
window with it. Apple describes the steps in
[Import and export Terminal profiles on Mac](https://support.apple.com/guide/terminal/import-and-export-terminal-profiles-trml4299c696/mac).

### The themes

<table>
  <tr>
    <td width="50%" align="center"><img src="Terminal/Renders/Aerogel.png" alt="The Aerogel theme in Terminal"><br><b>Aerogel</b> · <a href="Terminal/Themes/Peel%20Aerogel.terminal">Download</a></td>
    <td width="50%" align="center"><img src="Terminal/Renders/Anodise.png" alt="The Anodise theme in Terminal"><br><b>Anodise</b> · <a href="Terminal/Themes/Peel%20Anodise.terminal">Download</a></td>
  </tr>
  <tr>
    <td width="50%" align="center"><img src="Terminal/Renders/Borrow.png" alt="The Borrow theme in Terminal"><br><b>Borrow</b> · <a href="Terminal/Themes/Peel%20Borrow.terminal">Download</a></td>
    <td width="50%" align="center"><img src="Terminal/Renders/Cavitation.png" alt="The Cavitation theme in Terminal"><br><b>Cavitation</b> · <a href="Terminal/Themes/Peel%20Cavitation.terminal">Download</a></td>
  </tr>
  <tr>
    <td width="50%" align="center"><img src="Terminal/Renders/Cherenkov.png" alt="The Cherenkov theme in Terminal"><br><b>Cherenkov</b> · <a href="Terminal/Themes/Peel%20Cherenkov.terminal">Download</a></td>
    <td width="50%" align="center"><img src="Terminal/Renders/Cinnabar.png" alt="The Cinnabar theme in Terminal"><br><b>Cinnabar</b> · <a href="Terminal/Themes/Peel%20Cinnabar.terminal">Download</a></td>
  </tr>
  <tr>
    <td width="50%" align="center"><img src="Terminal/Renders/Cochineal.png" alt="The Cochineal theme in Terminal"><br><b>Cochineal</b> · <a href="Terminal/Themes/Peel%20Cochineal.terminal">Download</a></td>
    <td width="50%" align="center"><img src="Terminal/Renders/Coherence.png" alt="The Coherence theme in Terminal"><br><b>Coherence</b> · <a href="Terminal/Themes/Peel%20Coherence.terminal">Download</a></td>
  </tr>
  <tr>
    <td width="50%" align="center"><img src="Terminal/Renders/Coherence%20High%20Contrast.png" alt="The Coherence High Contrast theme in Terminal"><br><b>Coherence High Contrast</b> · <a href="Terminal/Themes/Peel%20Coherence%20High%20Contrast.terminal">Download</a></td>
    <td width="50%" align="center"><img src="Terminal/Renders/Dichroic.png" alt="The Dichroic theme in Terminal"><br><b>Dichroic</b> · <a href="Terminal/Themes/Peel%20Dichroic.terminal">Download</a></td>
  </tr>
  <tr>
    <td width="50%" align="center"><img src="Terminal/Renders/Effect.png" alt="The Effect theme in Terminal"><br><b>Effect</b> · <a href="Terminal/Themes/Peel%20Effect.terminal">Download</a></td>
    <td width="50%" align="center"><img src="Terminal/Renders/Epitaxy.png" alt="The Epitaxy theme in Terminal"><br><b>Epitaxy</b> · <a href="Terminal/Themes/Peel%20Epitaxy.terminal">Download</a></td>
  </tr>
  <tr>
    <td width="50%" align="center"><img src="Terminal/Renders/Fraunhofer.png" alt="The Fraunhofer theme in Terminal"><br><b>Fraunhofer</b> · <a href="Terminal/Themes/Peel%20Fraunhofer.terminal">Download</a></td>
    <td width="50%" align="center"><img src="Terminal/Renders/Glacier.png" alt="The Glacier theme in Terminal"><br><b>Glacier</b> · <a href="Terminal/Themes/Peel%20Glacier.terminal">Download</a></td>
  </tr>
  <tr>
    <td width="50%" align="center"><img src="Terminal/Renders/Hadal.png" alt="The Hadal theme in Terminal"><br><b>Hadal</b> · <a href="Terminal/Themes/Peel%20Hadal.terminal">Download</a></td>
    <td width="50%" align="center"><img src="Terminal/Renders/Incandescence.png" alt="The Incandescence theme in Terminal"><br><b>Incandescence</b> · <a href="Terminal/Themes/Peel%20Incandescence.terminal">Download</a></td>
  </tr>
  <tr>
    <td width="50%" align="center"><img src="Terminal/Renders/Noctiluca.png" alt="The Noctiluca theme in Terminal"><br><b>Noctiluca</b> · <a href="Terminal/Themes/Peel%20Noctiluca.terminal">Download</a></td>
    <td width="50%" align="center"><img src="Terminal/Renders/Palimpsest.png" alt="The Palimpsest theme in Terminal"><br><b>Palimpsest</b> · <a href="Terminal/Themes/Peel%20Palimpsest.terminal">Download</a></td>
  </tr>
  <tr>
    <td width="50%" align="center"><img src="Terminal/Renders/Passepartout.png" alt="The Passepartout theme in Terminal"><br><b>Passepartout</b> · <a href="Terminal/Themes/Peel%20Passepartout.terminal">Download</a></td>
    <td width="50%" align="center"><img src="Terminal/Renders/Persistence.png" alt="The Persistence theme in Terminal"><br><b>Persistence</b> · <a href="Terminal/Themes/Peel%20Persistence.terminal">Download</a></td>
  </tr>
  <tr>
    <td width="50%" align="center"><img src="Terminal/Renders/Provenance.png" alt="The Provenance theme in Terminal"><br><b>Provenance</b> · <a href="Terminal/Themes/Peel%20Provenance.terminal">Download</a></td>
    <td width="50%" align="center"><img src="Terminal/Renders/Quantum.png" alt="The Quantum theme in Terminal"><br><b>Quantum</b> · <a href="Terminal/Themes/Peel%20Quantum.terminal">Download</a></td>
  </tr>
  <tr>
    <td width="50%" align="center"><img src="Terminal/Renders/Riso.png" alt="The Riso theme in Terminal"><br><b>Riso</b> · <a href="Terminal/Themes/Peel%20Riso.terminal">Download</a></td>
    <td width="50%" align="center"><img src="Terminal/Renders/Safelight.png" alt="The Safelight theme in Terminal"><br><b>Safelight</b> · <a href="Terminal/Themes/Peel%20Safelight.terminal">Download</a></td>
  </tr>
  <tr>
    <td width="50%" align="center"><img src="Terminal/Renders/Selenium.png" alt="The Selenium theme in Terminal"><br><b>Selenium</b> · <a href="Terminal/Themes/Peel%20Selenium.terminal">Download</a></td>
    <td width="50%" align="center"><img src="Terminal/Renders/Silverpoint.png" alt="The Silverpoint theme in Terminal"><br><b>Silverpoint</b> · <a href="Terminal/Themes/Peel%20Silverpoint.terminal">Download</a></td>
  </tr>
  <tr>
    <td width="50%" align="center"><img src="Terminal/Renders/Stratum.png" alt="The Stratum theme in Terminal"><br><b>Stratum</b> · <a href="Terminal/Themes/Peel%20Stratum.terminal">Download</a></td>
    <td width="50%" align="center"><img src="Terminal/Renders/Valence.png" alt="The Valence theme in Terminal"><br><b>Valence</b> · <a href="Terminal/Themes/Peel%20Valence.terminal">Download</a></td>
  </tr>
  <tr>
    <td width="50%" align="center"><img src="Terminal/Renders/Verdigris.png" alt="The Verdigris theme in Terminal"><br><b>Verdigris</b> · <a href="Terminal/Themes/Peel%20Verdigris.terminal">Download</a></td>
    <td></td>
  </tr>
</table>

## Shell, Git, and SSH

Every setting on these tabs is one that zsh, Git, or ssh already has, and each has a switch. Peel never edits your
shell's or ssh's own files, and changes Git's only through Git itself:

- **zsh** reads Peel's settings from a file of Peel's own, `~/Library/Application Support/Peel/Terminal/zshrc`, once
  you add the line below to `~/.zshrc`. The Shell tab gives a command that adds it at the end. If you load tools
  such as fzf-tab there, move Peel's line above theirs, since their settings have to come after Peel's;
  zsh-syntax-highlighting's line stays the very last.
- **ssh** reads them from `~/Library/Application Support/Peel/Terminal/ssh_config`, once you add two lines at the end
  of `~/.ssh/config`. What you set for a server earlier in that file stays in force, since ssh uses the first value
  it finds.
- **Git**'s are changed with `git config --global`, Git's own command, and turning one off puts back what you had
  before Peel set it; a setting you made yourself goes back to Git's default.

The line that makes zsh read Peel's file:

```zsh
[[ -r "$HOME/Library/Application Support/Peel/Terminal/zshrc" ]] && source "$HOME/Library/Application Support/Peel/Terminal/zshrc"
```

Peel offers a setting only when the zsh, Git, or ssh on your Mac knows it, and Turn All Off on each tab undoes what
Peel set there; on the Git tab it also turns off what you set yourself, as its question says. Without Peel, add the
lines below to `~/.zshrc` or `~/.ssh/config` yourself, or run the `git config` commands.

### Prompt

The prompt is what zsh shows before each command you type. Peel builds it from parts you choose on the Shell tab:
what comes before the symbol, the Git branch, the symbol, whether the symbol turns red after a command that fails,
and whether the command starts a line of its own. The colors are the Terminal theme's, and the branch comes from
zsh's own [vcs_info](https://zsh.sourceforge.io/Doc/Release/User-Contributions.html#Version-Control-Information).
Peel writes no prompt until you turn on **Use Peel's prompt**. A prompt your `~/.zshrc` sets after Peel's line is the
one zsh shows, and the Shell tab says so when that line sets `PROMPT` or `PS1`.

<table>
  <tr>
    <td width="45%"><img src="Terminal/Prompts/folder.png" alt="A prompt with the folder, the branch, and a chevron"></td>
    <td><b>Folder</b><br>The folder you're in, <code>~</code> at home, then the branch and the symbol. This is the prompt Peel starts with.</td>
  </tr>
  <tr>
    <td width="45%"><img src="Terminal/Prompts/path.png" alt="A prompt with the path from the home folder"></td>
    <td><b>Path from your home folder</b><br>The whole path, from <code>~</code>.</td>
  </tr>
  <tr>
    <td width="45%"><img src="Terminal/Prompts/nameAndFolder.png" alt="A prompt with the name, the computer, and the folder"></td>
    <td><b>Your name, the computer, and the folder</b><br>As the prompt macOS sets begins, in color.</td>
  </tr>
  <tr>
    <td width="45%"><img src="Terminal/Prompts/ownLine.png" alt="A prompt whose symbol starts a line of its own"></td>
    <td><b>Command on its own line</b><br>The symbol starts a line of its own, so the command always has the whole width of the window.</td>
  </tr>
</table>

The symbol is one of `❯` `➜` `›` `▸` `»` `$` `%` `>`, each a character Unicode gives one column, so Terminal never
draws it over the command. Peel writes `%` as `%%`, since a single one starts zsh's own codes.

The lines a prompt with the branch adds:

```zsh
autoload -Uz vcs_info add-zsh-hook
zstyle ':vcs_info:*' enable git
zstyle ':vcs_info:git:*' formats ' %F{yellow}%b%f'
zstyle ':vcs_info:git:*' actionformats ' %F{yellow}%b%f %F{red}%a%f'
add-zsh-hook precmd vcs_info
setopt PROMPT_SUBST
```

Then the prompt itself, one line. These are the four above, and one with `%` that stays green after a failure:

```zsh
PROMPT='%F{cyan}%1~%f${vcs_info_msg_0_} %(?.%F{green}.%F{red})❯%f '
PROMPT='%F{cyan}%~%f${vcs_info_msg_0_} %(?.%F{green}.%F{red})❯%f '
PROMPT='%F{green}%n@%m%f %F{cyan}%1~%f${vcs_info_msg_0_} %(?.%F{green}.%F{red})❯%f '
PROMPT=$'%F{cyan}%1~%f${vcs_info_msg_0_}\n%(?.%F{green}.%F{red})❯%f '
PROMPT='%F{cyan}%1~%f${vcs_info_msg_0_} %F{green}%%%f '
```

### Shell

**History**

| Setting | What it does |
| --- | --- |
| [Remember 50,000 commands](https://zsh.sourceforge.io/Doc/Release/Parameters.html#index-HISTSIZE) | zsh keeps your last 50,000 commands and saves all of them, instead of keeping 2,000 and saving 1,000 as macOS sets it. |
| [Share history between windows](https://zsh.sourceforge.io/Doc/Release/Options.html#index-SHARE_005fHISTORY) | Each window adds its commands to the history as they run and reads the others', so the Up Arrow finds them in every window. |
| [Save when each command ran](https://zsh.sourceforge.io/Doc/Release/Options.html#index-EXTENDED_005fHISTORY) | Each command is saved with the time it started and how long it ran, which `history -iD` shows. |
| [Skip repeated commands](https://zsh.sourceforge.io/Doc/Release/Options.html#index-HIST_005fIGNORE_005fALL_005fDUPS) | When you run a command that is already in the history, the older copy goes, so each command appears once. |
| [Leave out commands that start with a space](https://zsh.sourceforge.io/Doc/Release/Options.html#index-HIST_005fIGNORE_005fSPACE) | A command typed after a space isn't saved, which keeps a password or token you type out of the history. |
| [Remove extra spaces](https://zsh.sourceforge.io/Doc/Release/Options.html#index-HIST_005fREDUCE_005fBLANKS) | Spaces a command doesn't need are taken out before it is saved. |
| [Check recalled commands first](https://zsh.sourceforge.io/Doc/Release/Options.html#index-HIST_005fVERIFY) | `!!` and the other history shortcuts put the command on the line for you to check, instead of running it at once. |
| [Lock the history file safely](https://zsh.sourceforge.io/Doc/Release/Options.html#index-HIST_005fFCNTL_005fLOCK) | Saving the history locks the file the system's way, so windows that save at the same time don't damage it. |

```zsh
# Remember 50,000 commands
HISTSIZE=50000
SAVEHIST=50000

# Share history between windows
setopt SHARE_HISTORY

# Save when each command ran
setopt EXTENDED_HISTORY

# Skip repeated commands
setopt HIST_IGNORE_ALL_DUPS

# Leave out commands that start with a space
setopt HIST_IGNORE_SPACE

# Remove extra spaces
setopt HIST_REDUCE_BLANKS

# Check recalled commands first
setopt HIST_VERIFY

# Lock the history file safely
setopt HIST_FCNTL_LOCK
```

**Typing**

| Setting | What it does |
| --- | --- |
| [Allow comments in commands](https://zsh.sourceforge.io/Doc/Release/Options.html#index-INTERACTIVE_005fCOMMENTS) | Anything after `#` on the command line is a comment, as in a script, so a pasted command with comments runs. |
| [Search history with the arrow keys](https://zsh.sourceforge.io/Doc/Release/User-Contributions.html#index-up_002dline_002dor_002dbeginning_002dsearch) | Type the start of a command, and the Up Arrow and Down Arrow go only through the commands that start that way, whichever of its two sequences an arrow key sends. |
| [Delete paths one folder at a time](https://zsh.sourceforge.io/Doc/Release/Parameters.html#index-WORDCHARS) | Deleting a word back stops at each slash, so a path goes one folder at a time. |

```zsh
# Allow comments in commands
setopt INTERACTIVE_COMMENTS

# Search history with the arrow keys
autoload -Uz up-line-or-beginning-search down-line-or-beginning-search
zle -N up-line-or-beginning-search
zle -N down-line-or-beginning-search
bindkey '^[[A' up-line-or-beginning-search
bindkey '^[OA' up-line-or-beginning-search
bindkey '^[[B' down-line-or-beginning-search
bindkey '^[OB' down-line-or-beginning-search

# Delete paths one folder at a time
WORDCHARS=${WORDCHARS//[\/]}
```

**Folders**

| Setting | What it does |
| --- | --- |
| [Go to a folder by typing its name](https://zsh.sourceforge.io/Doc/Release/Options.html#index-AUTO_005fCD) | Typing only a folder's name goes to it, as `cd` does. |
| [Remember the folders you visit](https://zsh.sourceforge.io/Doc/Release/Options.html#index-AUTO_005fPUSHD) | The folders you leave are remembered, each only once: `dirs -v` lists them, and `cd +1`, `cd +2`, and so on go back. |

```zsh
# Go to a folder by typing its name
setopt AUTO_CD

# Remember the folders you visit
setopt AUTO_PUSHD PUSHD_IGNORE_DUPS
```

**Completion**

| Setting | What it does |
| --- | --- |
| [Choose completions from a menu](https://zsh.sourceforge.io/Doc/Release/Completion-System.html#index-menu_002c-completion-style) | When Tab finds several completions, it opens a menu you move through with the arrow keys. |
| [Complete names in any case](https://zsh.sourceforge.io/Doc/Release/Completion-System.html#index-matcher_002dlist_002c-completion-style) | Tab completes a name whatever its case, so `doc` completes to `Documents`. |

The completion settings also start zsh's completion system, once, which the first line does.

```zsh
# Start the completion system once
(( $+functions[compdef] )) || { autoload -Uz compinit && compinit }

# Choose completions from a menu
zstyle ':completion:*' menu select

# Complete names in any case
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'
```

**Colors**

| Setting | What it does |
| --- | --- |
| Show colors in ls | `ls` shows folders, links, and programs in the Terminal theme's colors, as `man ls` describes `CLICOLOR`. |

```zsh
# Show colors in ls
export CLICOLOR=1
```

### Git

Peel uses the Git in the developer folder `xcode-select -p` names, from the Command Line Tools or Xcode, or else
Homebrew's, and offers only the settings that Git lists in `git help --config`. If Git isn't on your Mac, the Git
tab gives `xcode-select --install`, Apple's command for the tools.

**Pull and Push**

| Setting | What it does |
| --- | --- |
| [Rebase when pulling](https://git-scm.com/docs/git-config#Documentation/git-config.txt-pullrebase) | `git pull` puts your commits after what it fetched, instead of adding a merge commit. |
| [Push new branches without setting them up](https://git-scm.com/docs/git-config#Documentation/git-config.txt-pushautoSetupRemote) | `git push` on a new branch creates it on the remote and follows it, without `--set-upstream`. |
| [Remove branches deleted on the remote](https://git-scm.com/docs/git-config#Documentation/git-config.txt-fetchprune) | `git fetch` removes its copies of the branches deleted on the remote, and your own branches stay. |
| [Stash changes before a rebase](https://git-scm.com/docs/git-config#Documentation/git-config.txt-rebaseautoStash) | A rebase puts uncommitted changes aside and brings them back when it ends. |

```sh
# Rebase when pulling
git config --global pull.rebase true

# Push new branches without setting them up
git config --global push.autoSetupRemote true

# Remove branches deleted on the remote
git config --global fetch.prune true

# Stash changes before a rebase
git config --global rebase.autoStash true
```

**Diffs and Merges**

| Setting | What it does |
| --- | --- |
| [Use the histogram diff](https://git-scm.com/docs/git-config#Documentation/git-config.txt-diffalgorithm) | Diffs first match the lines that appear rarely, so changes line up around them. |
| [Color moved lines](https://git-scm.com/docs/git-config#Documentation/git-config.txt-diffcolorMoved) | Lines that moved without changing get colors of their own in a diff. |
| [Show the original in conflicts](https://git-scm.com/docs/git-config#Documentation/git-config.txt-mergeconflictStyle) | A conflict shows the lines as they were before both changes, between the two sides. |
| [Reuse conflict resolutions](https://git-scm.com/docs/git-config#Documentation/git-config.txt-rerereenabled) | Git remembers how you resolved a conflict and resolves the same conflict the same way next time. |

```sh
# Use the histogram diff
git config --global diff.algorithm histogram

# Color moved lines
git config --global diff.colorMoved default

# Show the original in conflicts
git config --global merge.conflictStyle zdiff3

# Reuse conflict resolutions
git config --global rerere.enabled true
```

**Branches**

| Setting | What it does |
| --- | --- |
| [Start new repositories on main](https://git-scm.com/docs/git-config#Documentation/git-config.txt-initdefaultBranch) | `git init` names the first branch main. |
| [List branches by latest commit](https://git-scm.com/docs/git-config#Documentation/git-config.txt-branchsort) | `git branch` lists the branches with the most recent commit first. |
| [Show lists in columns](https://git-scm.com/docs/git-config#Documentation/git-config.txt-columnui) | Commands such as `git branch` and `git tag` show their lists in columns when the window has room. |

```sh
# Start new repositories on main
git config --global init.defaultBranch main

# List branches by latest commit
git config --global branch.sort -committerdate

# Show lists in columns
git config --global column.ui auto
```

**Signing**

| Setting | What it does |
| --- | --- |
| [Sign commits with your SSH key](https://git-scm.com/docs/git-config#Documentation/git-config.txt-commitgpgSign) | Every commit is signed with your SSH key, and GitHub shows it as Verified once you add the key there as a signing key. Peel offers it when one of `id_ed25519.pub`, `id_ecdsa.pub` and `id_rsa.pub` is in `~/.ssh`, or when signing is already on, and uses the first of them. Turning it off stops the signing, and takes the format and the key back out only if Peel set them. |

```sh
# Sign commits with your SSH key
git config --global gpg.format ssh
git config --global user.signingKey ~/.ssh/id_ed25519.pub
git config --global commit.gpgSign true
```

### SSH

The two lines that make ssh read Peel's file go at the end of `~/.ssh/config`. `Match all` comes first so they
reach every server, even after a `Host` block:

```
Match all
  Include "~/Library/Application Support/Peel/Terminal/ssh_config"
```

| Setting | What it does |
| --- | --- |
| [Keep key passphrases in your keychain](https://developer.apple.com/library/archive/technotes/tn2449/_index.html) | ssh asks for a key's passphrase once, saves it in your keychain, and adds the key to the agent. `UseKeychain` is macOS's own. |
| [Keep connections alive](https://man.openbsd.org/ssh_config#ServerAliveInterval) | On a quiet connection, ssh checks on the server every minute, so a router doesn't drop it. |
| [Reuse connections to a server](https://man.openbsd.org/ssh_config#ControlMaster) | A new connection to a server you're already connected to opens at once through the first, which stays open 10 minutes after the last one ends. |

Without Peel, these lines can go at the end of `~/.ssh/config`, in a `Match all` block of their own:

```
Match all
  # Keep key passphrases in your keychain
  UseKeychain yes
  AddKeysToAgent yes

  # Keep connections alive
  ServerAliveInterval 60

  # Reuse connections to a server
  ControlMaster auto
  ControlPath ~/.ssh/cm-%C
  ControlPersist 10m
```

## Tools

Peel installs nothing: each tool comes with its Homebrew command and what its own documentation says to do after.
If Homebrew isn't on your Mac, the Tools tab says so and gives the command from [brew.sh](https://brew.sh). The lines
below use `$HOMEBREW_PREFIX`, as Homebrew's own notes do; Peel writes your Mac's Homebrew folder in its place.

### For the Shell

| Tool | What it does | Install |
| --- | --- | --- |
| [zsh-completions](https://github.com/zsh-users/zsh-completions) | Completions for many more commands. If zsh then warns about insecure folders, `brew info zsh-completions` says how to fix it. | `brew install zsh-completions` |
| [fzf-tab](https://github.com/Aloxaf/fzf-tab) | Tab completion in fzf, where typing narrows the list. It needs fzf. | `brew install fzf fzf-tab` |
| [zoxide](https://github.com/ajeetdsouza/zoxide) | `z` goes to a folder you use from part of its name, and `zi` lets you choose. | `brew install zoxide` |
| [fzf](https://github.com/junegunn/fzf) | Control-R searches your history and Control-T pastes files, and `--color=16` uses the Terminal theme's colors. | `brew install fzf` |
| [direnv](https://github.com/direnv/direnv) | Sets a project's environment variables in its folder, from its `.envrc` once you allow it with `direnv allow`. | `brew install direnv` |
| [zsh-autosuggestions](https://github.com/zsh-users/zsh-autosuggestions) | Suggests the rest of a command from your history. | `brew install zsh-autosuggestions` |
| [zsh-syntax-highlighting](https://github.com/zsh-users/zsh-syntax-highlighting) | Colors commands as you type them. | `brew install zsh-syntax-highlighting` |

Their lines go in `~/.zshrc` in this order, and zsh-syntax-highlighting's must be the last line.

```zsh
# zsh-completions
FPATH="$HOMEBREW_PREFIX/share/zsh-completions:$FPATH"
autoload -Uz compinit && compinit

# fzf-tab
source "$HOMEBREW_PREFIX/opt/fzf-tab/share/fzf-tab/fzf-tab.zsh"
zstyle ':completion:*' menu no

# zoxide
eval "$(zoxide init zsh)"

# fzf
source <(fzf --zsh)
export FZF_DEFAULT_OPTS="$FZF_DEFAULT_OPTS --color=16"

# direnv
eval "$(direnv hook zsh)"

# zsh-autosuggestions
source "$HOMEBREW_PREFIX/share/zsh-autosuggestions/zsh-autosuggestions.zsh"

# zsh-syntax-highlighting
source "$HOMEBREW_PREFIX/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
```

### For Git

| Tool | What it does | Install |
| --- | --- | --- |
| [delta](https://github.com/dandavison/delta) | Diffs with syntax highlighting and line numbers. | `brew install git-delta` |
| [Git LFS](https://github.com/git-lfs/git-lfs) | Works with repositories that keep large files in LFS. | `brew install git-lfs` |
| [lazygit](https://github.com/jesseduffield/lazygit) | A full Git interface inside Terminal: run `lazygit` in a repository. | `brew install lazygit` |

Then run these once in Terminal.

```sh
# delta
git config --global core.pager delta
git config --global interactive.diffFilter 'delta --color-only'
git config --global delta.navigate true

# Git LFS
git lfs install
```

### For Every Day

| Tool | What it does | Install |
| --- | --- | --- |
| [bat](https://github.com/sharkdp/bat) | Shows files with syntax highlighting, and colors manual pages. | `brew install bat` |
| [hyperfine](https://github.com/sharkdp/hyperfine) | Measures how long commands take, such as `hyperfine "zsh -i -c exit"` for a new shell. | `brew install hyperfine` |
| [tlrc](https://github.com/tldr-pages/tlrc) | Short, practical examples for a command: `tldr` followed by its name. | `brew install tlrc` |

bat's lines go in `~/.zshrc`. `col -bx` comes first because macOS's `man` marks bold text with backspaces, which bat
would show as they are.

```zsh
# bat
export BAT_THEME=ansi
export MANPAGER="sh -c 'col -bx | bat -l man -p'"
```

## Where the colors come from

<p align="center">
  <a href="https://github.com/TuguiDragos/tapetum"><img src="readme-assets/tapetum-fan-512.png" width="128" alt="Tapetum icon: a fan of color swatches"></a>
</p>

<h3 align="center">Tapetum</h3>

<p align="center">
  The palettes of these themes come from Tapetum, a free theme pack for VS Code and the editors built on it, by
  Țugui Dragoș: 58 themes in 28 families, each in dark and light, plus a high contrast pair for Coherence, with every
  color placed by hand and its contrast measured on the surface it sits on.
</p>

<p align="center">
  <a href="https://marketplace.visualstudio.com/items?itemName=tuguidragos.tapetum"><img src="https://img.shields.io/badge/Visual%20Studio%20Marketplace-201F1D?style=flat&logo=data%3Aimage%2Fsvg%2Bxml%3Bbase64%2CPHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCAyNCAyNCI%2BPGcgZmlsbD0ibm9uZSIgc3Ryb2tlPSIjRkY5OTMzIiBzdHJva2Utd2lkdGg9IjEuOSIgc3Ryb2tlLWxpbmVjYXA9InJvdW5kIiBzdHJva2UtbGluZWpvaW49InJvdW5kIj48cGF0aCBkPSJNMTIgNHYxMU03LjUgMTAuNSAxMiAxNWw0LjUtNC41TTUgMTkuNWgxNCIvPjwvZz48L3N2Zz4%3D" height="30" alt="Install Tapetum from the Visual Studio Marketplace"></a>
  <a href="https://open-vsx.org/extension/tuguidragos/tapetum"><img src="https://img.shields.io/badge/Open%20VSX-201F1D?style=flat&logo=data%3Aimage%2Fsvg%2Bxml%3Bbase64%2CPHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCAyNCAyNCI%2BPGcgZmlsbD0ibm9uZSIgc3Ryb2tlPSIjRkY5OTMzIiBzdHJva2Utd2lkdGg9IjEuOSIgc3Ryb2tlLWxpbmVjYXA9InJvdW5kIiBzdHJva2UtbGluZWpvaW49InJvdW5kIj48cGF0aCBkPSJNMTIgNHYxMU03LjUgMTAuNSAxMiAxNWw0LjUtNC41TTUgMTkuNWgxNCIvPjwvZz48L3N2Zz4%3D" height="30" alt="Install Tapetum from Open VSX"></a>
  <a href="https://github.com/TuguiDragos/tapetum"><img src="https://img.shields.io/badge/GitHub-201F1D?style=flat&logo=github&logoColor=FF9933" height="30" alt="Tapetum on GitHub"></a>
</p>
