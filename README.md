<p align="center">
  <img src="Logo/Peel-Dark.png" width="128" alt="Peel app icon">
</p>

<h1 align="center">Peel</h1>

<p align="center">
  <strong>Uninstall Mac apps completely, and see why every file belongs to them.</strong><br>
  A free, open source uninstaller and cleaner for macOS, which also fine-tunes your Mac and sets up Terminal.
</p>

<p align="center">
  <a href="https://github.com/TuguiDragos/Peel/releases/latest"><img src="https://img.shields.io/github/v/release/TuguiDragos/Peel?style=flat&label=Download&labelColor=201F1D&color=201F1D&logo=data%3Aimage%2Fsvg%2Bxml%3Bbase64%2CPHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCAyNCAyNCI%2BPGcgZmlsbD0ibm9uZSIgc3Ryb2tlPSIjRkY5OTMzIiBzdHJva2Utd2lkdGg9IjEuOSIgc3Ryb2tlLWxpbmVjYXA9InJvdW5kIiBzdHJva2UtbGluZWpvaW49InJvdW5kIj48cGF0aCBkPSJNMTIgNHYxMU03LjUgMTAuNSAxMiAxNWw0LjUtNC41TTUgMTkuNWgxNCIvPjwvZz48L3N2Zz4%3D" height="30" alt="Download the latest release"></a>
  <img src="https://img.shields.io/badge/macOS%2026%20or%20later-201F1D?style=flat&logo=apple&logoColor=FF9933" height="30" alt="Requires macOS 26 or later">
  <img src="https://img.shields.io/badge/18%20languages-201F1D?style=flat&logo=data%3Aimage%2Fsvg%2Bxml%3Bbase64%2CPHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCAyNCAyNCI%2BPGcgZmlsbD0ibm9uZSIgc3Ryb2tlPSIjRkY5OTMzIiBzdHJva2Utd2lkdGg9IjEuNyIgc3Ryb2tlLWxpbmVjYXA9InJvdW5kIj48Y2lyY2xlIGN4PSIxMiIgY3k9IjEyIiByPSI4LjYiLz48ZWxsaXBzZSBjeD0iMTIiIGN5PSIxMiIgcng9IjQuMSIgcnk9IjguNiIvPjxwYXRoIGQ9Ik0zLjkgOS4xaDE2LjJNMy45IDE0LjloMTYuMiIvPjwvZz48L3N2Zz4%3D" height="30" alt="Available in 18 languages">
  <a href="LICENSE"><img src="https://img.shields.io/badge/GPL%203.0%20or%20later-201F1D?style=flat&logo=data%3Aimage%2Fsvg%2Bxml%3Bbase64%2CPHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCAyNCAyNCI%2BPGcgZmlsbD0ibm9uZSIgc3Ryb2tlPSIjRkY5OTMzIiBzdHJva2Utd2lkdGg9IjEuNyIgc3Ryb2tlLWxpbmVjYXA9InJvdW5kIiBzdHJva2UtbGluZWpvaW49InJvdW5kIj48cGF0aCBkPSJNMTIgMy41djE2LjVNOCAyMGg4TTQuNSA3aDE1Ii8%2BPHBhdGggZD0iTTQuNSA3IDIgMTMuNWg1eiIvPjxwYXRoIGQ9Ik0xOS41IDcgMTcgMTMuNWg1eiIvPjwvZz48L3N2Zz4%3D" height="30" alt="License: GNU GPL 3.0 or later"></a>
</p>

## Install

> [!CAUTION]
> Peel is published in one place only: this repository,
> [github.com/TuguiDragos/Peel](https://github.com/TuguiDragos/Peel). Download it from its
> [releases](https://github.com/TuguiDragos/Peel/releases/latest) or with the Homebrew command below, which installs
> the same release. My only website is [tuguidragos.com](https://tuguidragos.com). Any other site, download page, or
> store offering Peel is not mine, and what it gives you may not be the app I build and sign. Peel is free, so anyone
> asking you to pay for it is not me. Please download it only from here.

**Requirements:** macOS Tahoe 26 or later, on a Mac with Apple silicon or an Intel processor. Peel moves your
files, so I test every release myself before it ships, and I can't test it on an older macOS. It never runs where
it hasn't been tested, which is why it starts at macOS 26.

### Download

1. Download `Peel-<version>.dmg` from the [latest release](https://github.com/TuguiDragos/Peel/releases/latest).
2. Open it and drag Peel into your Applications folder.
3. Open Peel. It's signed by its developer and notarized by Apple, so it opens like any app you download from
   the web.

### Homebrew

```bash
brew install --cask tuguidragos/tap/peel
```

Homebrew also puts the `peel` command on your path.

To update Peel, download the new release and replace the copy in your Applications folder, or run
`brew upgrade --cask peel`.

## Why Peel

Dragging an app to the Trash leaves pieces of it behind: caches, settings, containers, launch agents, and support
files scattered across your Library, sometimes gigabytes of them. Peel finds what an app left, tells you why each
file belongs to it and how sure it is, and moves what you choose to the Trash. Nothing is deleted, and History can
put all of it back.

Peel is free and open source, and it speaks English and 17 other languages.

## What Peel does

[GUIDE.md](GUIDE.md) shows what each tool does, what Peel asks for and why, and how to remove Peel.

## Safe by design

<p align="center">
  <img src="readme-assets/peel-history-put-back-from-trash.png" width="900" alt="Peel's History: Godot with its app, caches, support folder, and the command Homebrew linked to it, moved to the Trash yesterday, each item ready to put back, and under Not Moved, what Peel was asked to move and didn't">
</p>

A cleaner should never cost you something you wanted. Peel is built around that.

- **The Trash, never deletion.** Everything Peel removes goes to the Trash, and History puts it back where it was.
  Three things can't be undone that way, and Peel says so before you confirm them: Homebrew's own uninstall and
  cleanup, and resetting an app's privacy permissions.
- **Protected places stay protected.** Peel refuses to move iCloud Drive, keychains, your SSH and signing keys, the
  keys of crypto wallets, Mail, Messages, Safari, Contacts, Calendars, Notes, photo and music libraries, iPhone and
  iPad backups, and the Desktop, Documents, and Downloads folders themselves. No selection can override it.
- **Crypto wallets are never selected for you.** Beyond the places wallets keep their keys, a browser profile with
  a wallet extension such as MetaMask stays where it is, so uninstalling a browser never takes a wallet with it.
  A folder an uninstall or Orphaned Files finds a wallet or a signing key in is shown with that reason and moves
  only if you select it yourself. [SAFETY.md](SAFETY.md#crypto-wallets) says how Peel knows one.
- **Checked again at the last moment.** Peel looks at each item once more right before it moves, so something
  swapped in the meantime stays where it is.
- **Nothing shared, nothing unknown.** A file another app also uses is never selected for you. A folder Peel
  couldn't measure or read is shown as unknown, never as empty, and never selected for you either.
- **Your exclusions, everywhere.** What you exclude never appears in any list, and a folder holding something you
  excluded is never moved.
- **Every decision explained.** When Peel holds a file back, the row says why.

[SAFETY.md](SAFETY.md) lists everything Peel protects, and [ARCHITECTURE.md](ARCHITECTURE.md) shows how a
removal travels through the code.

## Privacy

Peel sends no analytics and has no account. [PRIVACY.md](PRIVACY.md) says when Peel goes online, what it sends, and
every address Peel or Homebrew may contact.

## The `peel` command

The command ships inside the app. Settings > General shows the Terminal command that puts it on your path, and a
Homebrew install puts it there for you.

Every command that moves something asks first, and takes `--dry-run` to only show the plan and `-y` to skip the
question. It asks only where you can see the plan and answer, so with its output sent to a file or a pipe it needs
`-y`, and it ignores keys typed before the question appeared. Answering no exits with code 2, so
`peel uninstall Foo && next-step` stops there. The command moves only what the app would suggest, through the same
checks, into the same History, and leaves anything that needs an administrator to the app. It won't run under
`sudo`. Most commands take `--json`, which lists without moving, and `peel uninstall --json` reports what moved,
what stayed, and why. A Homebrew install also sets up its completions for zsh, bash, and fish and its manual page,
`man peel`; otherwise `peel --generate-completion-script zsh` writes the completions for your shell.

<details>
<summary>All commands</summary>

<br>

| Command | What it does |
|---|---|
| `peel apps` | Lists installed apps. |
| `peel inventory` | Writes out what is installed and where each app came from, as text, JSON, CSV, or a Brewfile. |
| `peel leftovers <app>` | Shows the files an app leaves behind, and why each one belongs to it. |
| `peel uninstall <app>` | Moves an app and its leftovers to the Trash, and takes its icon out of the Dock unless `--keep-in-dock` is given. `--reset-privacy` also clears the permissions macOS gave it. |
| `peel orphans` | Lists files left by apps that are no longer installed. `--remove <group>` moves one group. |
| `peel caches` | Lists the caches of developer tools. `--remove` moves the ones Peel suggests. |
| `peel projects <folders>` | Lists what builds left in your projects. `--remove` moves the ones Peel suggests. |
| `peel duplicates [folders]` | Finds files and folders with identical contents. `--remove` keeps one copy of each and moves the rest. |
| `peel search` | Searches Spotlight by name, kind, size, or age. |
| `peel updates` | Checks your apps for updates. |
| `peel history` | Lists what Peel moved to the Trash, from the app and from Terminal alike. `--refused` lists what it was asked to move and wouldn't, and why. |
| `peel restore <id>` | Puts one of those removals back. |
| `peel exclusions` | Shows what Peel leaves alone. `add` and `remove` change it. |

</details>

## Frequently asked questions

<details>
<summary><strong>How do I completely uninstall an app on a Mac?</strong></summary>

<br>

Open Peel, choose the app under Applications, look over what Peel found, and click Move to Trash. The app and its
leftovers go to the Trash together, and History can put them back. You can also Control-click the app in Finder
and choose Uninstall with Peel.

</details>

<details>
<summary><strong>Can Peel delete something I need?</strong></summary>

<br>

Peel moves files to the Trash instead of deleting them, and History can put any removal back. It selects only what
certainly belongs to the app, never selects a file another app uses, and refuses to touch places like iCloud Drive,
your keychains, Mail, Messages, and photo libraries.

</details>

<details>
<summary><strong>Does Peel collect any data?</strong></summary>

<br>

No. Peel has no analytics and no account. It goes online only to check your apps for updates, which you can turn
off, and when you ask Homebrew to do something.

</details>

<details>
<summary><strong>Does Peel work on Intel Macs and older versions of macOS?</strong></summary>

<br>

Peel runs on Intel Macs and Macs with Apple silicon, on macOS Tahoe 26 or later. It doesn't run on earlier
versions of macOS: I test every release myself before it ships, and I can't test it on an older macOS, so Peel
never runs where it hasn't been tested.

</details>

## Build it yourself

You need macOS Tahoe 26 or later, Xcode 27 (Swift 6.4), and a team to sign with, even a free one. Open
`Peel.xcodeproj`, choose your team for the four targets under Signing & Capabilities, and run the Peel scheme. Or,
from Terminal, with your own team ID:

```bash
xcodebuild -project Peel.xcodeproj -scheme Peel -configuration Debug -derivedDataPath build/DerivedData DEVELOPMENT_TEAM=YOUR_TEAM_ID build
swift test --package-path Packages/PeelCore
```

[ARCHITECTURE.md](ARCHITECTURE.md) explains how Peel is put together, and [CONTRIBUTING.md](CONTRIBUTING.md) what a
change needs.

## Contributing

Bug reports, ideas, and pull requests are welcome.

- Found a bug or have an idea? [Open an issue](https://github.com/TuguiDragos/Peel/issues/new/choose).
- Found a security problem? Please report it privately, as [SECURITY.md](SECURITY.md) describes, and not in a
  public issue.
- Everyone taking part is expected to follow the [Code of Conduct](CODE_OF_CONDUCT.md).

## Thank you

Peel would never have existed without the work, the generosity, and the ideas of others. To each of you, thank you
with all my heart.

- [blobatar](https://github.com/Alain00/blobatar), by Alain, for the animations that bring Peel's face to life:
  every breath, glance, and smile it makes began there.
- [Swift Argument Parser](https://github.com/apple/swift-argument-parser), by Apple, which every `peel` command is
  built on.
- [AppCleaner](https://freemacsoft.net/appcleaner/), by FreeMacSoft, and
  [Pearcleaner](https://github.com/alienator88/Pearcleaner), by alienator88, for the inspiration.
- [Fable](https://claude.com/product/overview), by [Anthropic](https://www.anthropic.com), for the help, the
  execution, and the many fine touches.
- Every [contributor](https://github.com/TuguiDragos/Peel/graphs/contributors) and every sponsor of this project,
  for your time, your ideas, and your trust.

Without you, this project would never have been possible. I bow to you all. ❤️

## License

Peel is free software under the [GNU General Public License, version 3 or later](LICENSE). You may use, study,
change, and share it. If you share a changed version, it has to carry the same freedoms: nobody can take Peel,
close it, and sell it as their own.

Copyright (C) 2026 [Țugui Dragoș-Constantin](https://tuguidragos.com)

Peel moves what it removes to the Trash, and History can put it back. As the GPL states, it comes with no warranty,
to the extent the law allows.

swift-argument-parser, Peel's only dependency, is by Apple Inc. under the Apache License 2.0. The motion of the
face at the head of the sidebar is ported from [blobatar](https://github.com/Alain00/blobatar), by Alain, under the
MIT License. Both licenses ship inside the app and are kept in `Peel/Licenses/`.

## More from Țugui Dragoș

<p align="center">
  <a href="https://tuguidragos.com"><img src="https://img.shields.io/badge/tuguidragos.com-201F1D?style=flat&logo=data%3Aimage%2Fsvg%2Bxml%3Bbase64%2CPHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCAyNCAyNCI%2BPGcgZmlsbD0ibm9uZSIgc3Ryb2tlPSIjRkY5OTMzIiBzdHJva2Utd2lkdGg9IjEuNyIgc3Ryb2tlLWxpbmVjYXA9InJvdW5kIj48Y2lyY2xlIGN4PSIxMiIgY3k9IjEyIiByPSI4LjYiLz48ZWxsaXBzZSBjeD0iMTIiIGN5PSIxMiIgcng9IjQuMSIgcnk9IjguNiIvPjxwYXRoIGQ9Ik0zLjkgOS4xaDE2LjJNMy45IDE0LjloMTYuMiIvPjwvZz48L3N2Zz4%3D" height="30" alt="Website"></a>
  <a href="https://www.linkedin.com/in/tuguidragos/"><img src="https://img.shields.io/badge/LinkedIn-201F1D?style=flat&logo=data%3Aimage%2Fsvg%2Bxml%3Bbase64%2CPHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCAyNCAyNCI%2BPGcgdHJhbnNmb3JtPSJ0cmFuc2xhdGUoMSAtMC45NCkgc2NhbGUoMC45NCkiPjxwYXRoIGZpbGw9IiNGRjk5MzMiIGQ9Ik00Ljk4IDMuNWEyLjUgMi41IDAgMSAxLTUgMCAyLjUgMi41IDAgMCAxIDUgMHpNLjIyIDguOThoNC41MlYyNEguMjJ6TTkuMjQgOC45OGg0LjM0djIuMDVoLjA2Yy42LTEuMTQgMi4wNy0yLjM0IDQuMjYtMi4zNCA0LjU2IDAgNS40IDMgNS40IDYuOVYyNGgtNC41MnYtNy41YzAtMS43OS0uMDMtNC4wOS0yLjQ5LTQuMDktMi40OSAwLTIuODcgMS45NS0yLjg3IDMuOTZWMjRIOS4yNHoiLz48L2c%2BPC9zdmc%2B" height="30" alt="LinkedIn"></a>
  <a href="https://www.instagram.com/tuguidragos/"><img src="https://img.shields.io/badge/Instagram-201F1D?style=flat&logo=instagram&logoColor=FF9933" height="30" alt="Instagram"></a>
  <a href="https://n8n.io/creators/tuguidragos/"><img src="https://img.shields.io/badge/n8n%20creator-201F1D?style=flat&logo=n8n&logoColor=FF9933" height="30" alt="n8n creator"></a>
  <a href="https://www.credly.com/users/tuguidragos"><img src="https://img.shields.io/badge/Credly-201F1D?style=flat&logo=credly&logoColor=FF9933" height="30" alt="Credly"></a>
</p>

<p align="center">
  <a href="https://github.com/TuguiDragos/tapetum"><img src="readme-assets/tapetum-fan-512.png" width="128" alt="Tapetum icon: a fan of color swatches"></a>
</p>

<h3 align="center">Tapetum</h3>

<p align="center">
  Spend your days in VS Code, or in an editor built on it? Try Tapetum, my free theme pack: 58 themes in 28
  families, each in dark and light, with every color placed by hand and its contrast measured on the surface it sits
  on.
</p>

<p align="center">
  <a href="https://marketplace.visualstudio.com/items?itemName=tuguidragos.tapetum"><img src="https://img.shields.io/badge/Visual%20Studio%20Marketplace-201F1D?style=flat&logo=data%3Aimage%2Fsvg%2Bxml%3Bbase64%2CPHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCAyNCAyNCI%2BPGcgZmlsbD0ibm9uZSIgc3Ryb2tlPSIjRkY5OTMzIiBzdHJva2Utd2lkdGg9IjEuOSIgc3Ryb2tlLWxpbmVjYXA9InJvdW5kIiBzdHJva2UtbGluZWpvaW49InJvdW5kIj48cGF0aCBkPSJNMTIgNHYxMU03LjUgMTAuNSAxMiAxNWw0LjUtNC41TTUgMTkuNWgxNCIvPjwvZz48L3N2Zz4%3D" height="30" alt="Install Tapetum from the Visual Studio Marketplace"></a>
  <a href="https://open-vsx.org/extension/tuguidragos/tapetum"><img src="https://img.shields.io/badge/Open%20VSX-201F1D?style=flat&logo=data%3Aimage%2Fsvg%2Bxml%3Bbase64%2CPHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCAyNCAyNCI%2BPGcgZmlsbD0ibm9uZSIgc3Ryb2tlPSIjRkY5OTMzIiBzdHJva2Utd2lkdGg9IjEuOSIgc3Ryb2tlLWxpbmVjYXA9InJvdW5kIiBzdHJva2UtbGluZWpvaW49InJvdW5kIj48cGF0aCBkPSJNMTIgNHYxMU03LjUgMTAuNSAxMiAxNWw0LjUtNC41TTUgMTkuNWgxNCIvPjwvZz48L3N2Zz4%3D" height="30" alt="Install Tapetum from Open VSX"></a>
  <a href="https://github.com/TuguiDragos/tapetum"><img src="https://img.shields.io/badge/GitHub-201F1D?style=flat&logo=github&logoColor=FF9933" height="30" alt="Tapetum on GitHub"></a>
</p>
