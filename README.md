<p align="center">
  <img src="Logo/Peel-Dark.png" width="128" alt="Peel app icon">
</p>

<h1 align="center">Peel</h1>

<p align="center">
  <strong>Uninstall Mac apps completely, and see why every file belongs to them.</strong><br>
  A free, open source app uninstaller and cleaner for macOS.
</p>

<p align="center">
  <a href="https://github.com/TuguiDragos/Peel/releases/latest"><img src="https://img.shields.io/github/v/release/TuguiDragos/Peel?label=download&color=f28c28&logo=data%3Aimage%2Fsvg%2Bxml%3Bbase64%2CPHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCAyNCAyNCI%2BPGcgZmlsbD0ibm9uZSIgc3Ryb2tlPSIjZmZmIiBzdHJva2Utd2lkdGg9IjEuOSIgc3Ryb2tlLWxpbmVjYXA9InJvdW5kIiBzdHJva2UtbGluZWpvaW49InJvdW5kIj48cGF0aCBkPSJNMTIgNHYxMU03LjUgMTAuNSAxMiAxNWw0LjUtNC41TTUgMTkuNWgxNCIvPjwvZz48L3N2Zz4%3D" alt="Download the latest release"></a>
  <img src="https://img.shields.io/badge/macOS-26%20or%20later-1f1f1f?logo=apple&logoColor=white" alt="Requires macOS 26 or later">
  <img src="https://img.shields.io/badge/languages-18-1f1f1f?logo=data%3Aimage%2Fsvg%2Bxml%3Bbase64%2CPHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCAyNCAyNCI%2BPGcgZmlsbD0ibm9uZSIgc3Ryb2tlPSIjZmZmIiBzdHJva2Utd2lkdGg9IjEuNyIgc3Ryb2tlLWxpbmVjYXA9InJvdW5kIj48Y2lyY2xlIGN4PSIxMiIgY3k9IjEyIiByPSI4LjYiLz48ZWxsaXBzZSBjeD0iMTIiIGN5PSIxMiIgcng9IjQuMSIgcnk9IjguNiIvPjxwYXRoIGQ9Ik0zLjkgOS4xaDE2LjJNMy45IDE0LjloMTYuMiIvPjwvZz48L3N2Zz4%3D" alt="Available in 18 languages">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-GPL%203.0%20or%20later-1f1f1f?logo=data%3Aimage%2Fsvg%2Bxml%3Bbase64%2CPHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCAyNCAyNCI%2BPGcgZmlsbD0ibm9uZSIgc3Ryb2tlPSIjZmZmIiBzdHJva2Utd2lkdGg9IjEuNyIgc3Ryb2tlLWxpbmVjYXA9InJvdW5kIiBzdHJva2UtbGluZWpvaW49InJvdW5kIj48cGF0aCBkPSJNMTIgMy41djE2LjVNOCAyMGg4TTQuNSA3aDE1Ii8%2BPHBhdGggZD0iTTQuNSA3IDIgMTMuNWg1eiIvPjxwYXRoIGQ9Ik0xOS41IDcgMTcgMTMuNWg1eiIvPjwvZz48L3N2Zz4%3D" alt="License: GNU GPL 3.0 or later"></a>
</p>

## Install

**Requirements:** macOS Tahoe 26 or later, on a Mac with Apple silicon or an Intel processor.

### Download

1. Download `Peel-<version>.zip` from the [latest release](https://github.com/TuguiDragos/Peel/releases/latest).
2. Open the zip and drag Peel into your Applications folder.
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

<p align="center">
  <img src="readme-assets/peel-home-permissions-and-disk-space.png" width="900" alt="Peel's Home: this Mac's chip, memory, and free space, what Peel has moved to the Trash so far, and which permissions are on">
</p>

Dragging an app to the Trash leaves pieces of it behind: caches, settings, containers, launch agents, and support
files scattered across your Library, sometimes gigabytes of them. Peel finds what an app left, tells you why each
file belongs to it and how sure it is, and moves what you choose to the Trash. Nothing is deleted, and History can
put all of it back.

Peel is free and open source, and it speaks English and 17 other languages.

## What Peel does

### Uninstall apps completely

<p align="center">
  <img src="readme-assets/peel-uninstall-app-with-leftover-files.png" width="900" alt="Peel uninstalling Blender: the app and its leftover files in caches, Application Support, and containers, each with its kind and size, selected and ready to move to the Trash">
</p>

- **Every leftover, with a reason.** Peel searches the places apps keep files: Application Support, caches,
  containers and group containers, preferences, saved state, logs, launch agents and daemons, plug-in folders, and
  more. Each file comes with the reason it matched, such as the app's bundle identifier, its signing team, or a
  Homebrew cask that names it.
- **Only the sure things are selected.** Files that certainly belong to the app are selected for you, unless
  Peel sees something inside that may exist nowhere else, such as a crypto wallet, a signing key, or a
  repository. A file another installed app also uses is shown but never selected, and anything Peel is less sure
  of waits under Review Before Removing.
- **Several ways in.** Choose an app in the list, drop one on Peel's Dock icon, select several apps at once, or
  Control-click an app in Finder and choose Uninstall with Peel. With Watch the Trash on, Peel notices when you
  drag an app to the Trash yourself and offers to clear what it left behind.
- **Reset instead of remove.** Clear an app's settings without uninstalling it. Peel saves them first, so you can
  put them back, and never selects your own work.
- **Privacy permissions too, if you want.** Peel can also reset the permissions macOS gave the app, such as access
  to the camera and the microphone.
- **Updates for your apps.** Peel checks your apps for new versions, through the update feed each app names or the
  App Store for apps bought there. Skip This Version and Never Check This App keep it quiet about the ones you
  want left alone.

### Free up disk space

- **Orphaned Files:** files left behind by apps you already removed.
- **Developer:** caches of Xcode, package managers, editors, cloud tools, and AI models. Model weights and virtual
  environments are listed but never selected for you, and toolchains or anything holding an account are never
  listed.
- **Build Artifacts:** what builds left in the folders you choose, like `node_modules`, `DerivedData`, and
  `target`. A project changed in the last 7 days is never selected for you.
- **Duplicates:** files and whole folders with identical contents, compared with SHA-256. One copy is always kept.
- **Installers and Backups:** installers of apps you already have, macOS installers, device firmware, and what your
  iPhone backups hold. Nothing is selected for you.
- **iCloud Drive:** files already safe in iCloud that are also downloaded to this Mac. Remove Downloads, as in
  Finder, takes away only the copy on this Mac: each file stays in iCloud and downloads again when you open it.
- **Space:** what's taking up room, and which app it belongs to.
- **File Search:** large or old files, found through Spotlight.

### Look after your Mac

<p align="center">
  <img src="readme-assets/peel-homebrew-updates-and-cleanup.png" width="900" alt="Peel's Homebrew page: Homebrew's version and location, its maintenance buttons, the packages with updates waiting, and an ⓘ note explaining updates">
</p>

> [!TIP]
> Not sure what something means? Click the ⓘ next to its name, like the one open above beside Updates Available,
> for a short explanation in plain words. Next to a file, it tells you why Peel thinks the file belongs to the app.

- **Background Items:** launch agents and daemons, and the app that added each one.
- **Extensions and Plug-ins:** app extensions, system extensions, and plug-ins, from audio units to Quick Look.
- **Package Receipts:** what installer packages put on your Mac, item by item.
- **Intel Software:** everything that still needs Rosetta, including helpers hidden inside universal apps.
- **Homebrew:** your formulae and casks, with Update, Clean Up, Check Health, Scan for Vulnerabilities, Upgrade,
  and Uninstall.

### Fine-tune your Mac

<p align="center">
  <img src="readme-assets/peel-tweaks-hidden-macos-settings.png" width="900" alt="Peel's Tweaks page, on Screenshots: no floating thumbnail after a screenshot, where screenshots are saved, no shadow around a captured window, names without the date, and JPEG instead of PNG, each with its own switch">
</p>

Small tricks that make everyday life on a Mac a little easier. Tweaks gathers 36 settings macOS already has but
keeps out of sight, in six groups: Dock, Screenshots, Finder, Typing, Windows, and Privacy. Make a hidden Dock
appear at once, save screenshots where you want them and without the floating thumbnail, show hidden files and
every file extension in Finder, keep straight quotes as you type, drag a window from anywhere in it, or put
seconds on the menu bar clock. Each tweak says what it changes, and turning it off puts back what was there
before, or leaves it to macOS.

### Stay in control

- **History:** everything Peel moved to the Trash, ready to put back, from the app and from Terminal alike, and
  what it was asked to move and wouldn't, with the reason for each item.
- **Exclusions:** files, folders, and apps Peel must never touch.

### Work your way

- **Export:** what's installed and where each app came from, as JSON, a spreadsheet, plain text, or a Brewfile.
- **Shortcuts:** actions that open a page in Peel for you to look at. None of them removes anything.
- **Sidebar:** turn off the tools you don't use in Settings, and they leave the sidebar. The View menu and
  Shortcuts still open them.
- **The `peel` command:** most of the above, from Terminal.

## Safe by design

<p align="center">
  <img src="readme-assets/peel-history-put-back-from-trash.png" width="900" alt="Peel's History: VLC with its preferences and caches, moved to the Trash seconds ago, each item ready to put back">
</p>

A cleaner should never cost you something you wanted. Peel is built around that.

- **The Trash, never deletion.** Everything Peel removes goes to the Trash, and History puts it back where it was.
  Three things can't be undone that way, and Peel says so before you confirm them: Homebrew's own uninstall and
  cleanup, and resetting an app's privacy permissions.
- **Protected places stay protected.** Peel refuses to move iCloud Drive, keychains, your SSH and signing keys, the
  keys of crypto wallets, Mail, Messages, Safari, Contacts, Calendars, Notes, photo and music libraries, iPhone and
  iPad backups, and the Desktop, Documents, and Downloads folders themselves. No selection can override it.
- **Crypto wallets are never selected for you.** Beyond the places wallets keep their keys, a folder an uninstall
  or Orphaned Files finds a wallet or a signing key in is shown with that reason and moves only if you select it
  yourself. [SAFETY.md](SAFETY.md#crypto-wallets) says how Peel knows one.
- **Checked again at the last moment.** Peel looks at each item once more right before it moves, so something
  swapped in the meantime stays where it is.
- **Nothing shared, nothing unknown.** A file another app also uses is never selected for you. A folder Peel
  couldn't measure or read is shown as unknown, never as empty, and never selected for you either.
- **Your exclusions, everywhere.** What you exclude never appears in any list, and a folder holding something you
  excluded is never moved.
- **Every decision explained.** When Peel holds a file back, the row says why.

[SAFETY.md](SAFETY.md) lists everything Peel protects, and [ARCHITECTURE.md](ARCHITECTURE.md) shows how a
removal travels through the code.

## What Peel asks for, and why

Peel opens without any of these and does more with each one. Home, the first picture on this page, shows which ones
are on and takes you straight to the right place in System Settings.

| Permission | What it lets Peel do |
|---|---|
| Full Disk Access | Look inside the Trash and the private folders where apps keep their data. Without it, Peel can't find everything an app leaves behind. |
| App Management | Move another developer's app to the Trash. Without it, Peel can still clear an app's files, but macOS may refuse to move the app itself. |
| Helper | Move the leftovers that sit in folders only an administrator can change, and start or stop other developers' background items that run as root. macOS asks you to approve it once, in Login Items & Extensions. |
| Notifications (optional) | Tell you when your apps have updates, and, with Watch the Trash on, when you move an app to the Trash yourself. |
| Finder extension (optional) | Add Uninstall with Peel to the menu you get when you Control-click an app in Finder. |
| Open at Login (optional) | Start Peel when you log in, so Watch the Trash keeps working. |

## Languages

Peel is in English and translated into 17 languages: Romanian, German, French, Spanish, Portuguese (Brazilian),
Italian, Japanese, Chinese (Simplified), Chinese (Traditional), Dutch, Korean, Russian, Polish, Turkish, Swedish,
Czech, and Ukrainian. It uses the first language in your Mac's list that it speaks, and English for any other. Each
translation uses the words macOS itself uses in that language.

To use Peel in a language other than your Mac's, open System Settings > General > Language & Region, click the Add
button under Applications, and choose Peel and a language. The `peel` command stays in English, since scripts read
it.

## Privacy

Peel sends no analytics and has no account. On its own, it goes online only to check your apps for updates, and
you can turn that off. Each check asks one app's own update feed about that app alone, or the App Store about an
app bought there. Homebrew goes online only when you ask it to update, upgrade, or scan for vulnerabilities, and
that scan is the one time a list of what is installed leaves your Mac: the name and version of each Homebrew
formula, sent to `api.osv.dev`. Turn off Check for app updates in Settings, and Peel contacts nothing on its own.

<details>
<summary>Every address Peel or Homebrew may contact</summary>

<br>

Settings > Privacy lists the same places.

| Address | Why |
|---|---|
| `itunes.apple.com` | The latest version of an app bought from the App Store. No other app is ever asked about. |
| `github.com` | Release feeds of apps that update through GitHub, and wherever GitHub sends the download. Homebrew also updates itself from here when you ask it to. |
| `formulae.brew.sh` | Homebrew's list of packages, when you ask Homebrew to update or upgrade. |
| `ghcr.io` | Where Homebrew downloads the packages it upgrades. A cask comes from its maker's own address. |
| `api.osv.dev` | The database of known vulnerabilities that Homebrew's scan checks your formulae against. |
| Each app's own update feed | The address written inside the app, such as a Sparkle feed, and wherever it redirects. |

</details>

## The `peel` command

The command ships inside the app. Settings > General shows the Terminal command that puts it on your path, and a
Homebrew install puts it there for you.

Every command that moves something asks first, and takes `--dry-run` to only show the plan and `-y` to skip the
question. Answering no exits with code 2, so `peel uninstall Foo && next-step` stops there. The command moves only
what the app would suggest, through the same checks, into the same History, and leaves anything that needs an
administrator to the app. It won't run under `sudo`. Most commands take `--json`, which lists without moving, and
`peel --generate-completion-script zsh` writes completions for your shell.

<details>
<summary>All commands</summary>

<br>

| Command | What it does |
|---|---|
| `peel apps` | Lists installed apps. |
| `peel inventory` | Writes out what is installed and where each app came from, as text, JSON, CSV, or a Brewfile. |
| `peel leftovers <app>` | Shows the files an app leaves behind, and why each one belongs to it. |
| `peel uninstall <app>` | Moves an app and its leftovers to the Trash. `--reset-privacy` also clears the permissions macOS gave it. |
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
<summary><strong>Why does Peel ask for Full Disk Access?</strong></summary>

<br>

macOS keeps other apps' data, and the Trash, out of sight of any app without it. Peel works without it, but can't
see everything an app leaves behind. [Privacy](#privacy) lists the only times Peel goes online.

</details>

<details>
<summary><strong>Does Peel collect any data?</strong></summary>

<br>

No. Peel has no analytics and no account. It goes online only to check your apps for updates, which you can turn
off, and when you ask Homebrew to do something.

</details>

<details>
<summary><strong>Is Peel really free?</strong></summary>

<br>

Yes. Peel is free and open source under the GNU General Public License, with no paid edition, no ads, and no
account.

</details>

<details>
<summary><strong>Is Peel an alternative to AppCleaner or CleanMyMac?</strong></summary>

<br>

It does the same job of removing apps together with what they leave behind. Peel is free and open source, shows why
each file belongs to the app and how sure it is, and moves everything to the Trash, where History can put it back.

</details>

<details>
<summary><strong>Does Peel work on Intel Macs and older versions of macOS?</strong></summary>

<br>

Peel runs on Intel Macs and Macs with Apple silicon, on macOS Tahoe 26 or later. It doesn't run on earlier
versions of macOS.

</details>

<details>
<summary><strong>Something in Peel isn't clear. Where can I read more?</strong></summary>

<br>

Click the ⓘ next to its name. If it's still not clear,
[open an issue](https://github.com/TuguiDragos/Peel/issues/new/choose): wording that leaves you guessing is a bug
too.

</details>

## Uninstall Peel

In Settings > General, choose Remove Peel. It removes its helper and its login item, moves itself, the files that
are certainly its own, and its folder in Application Support to the Trash, clears its settings, and quits. That
folder holds History, your exclusions, and the settings Peel saved when you reset an app.

If you installed Peel with Homebrew, Settings shows this command in its place, with a button that copies it. Run it
in Terminal: Homebrew takes Peel off its list of what is installed, deletes the app rather than moving it to the
Trash, and moves Peel's files to the Trash.

```bash
brew uninstall --zap --cask peel
```

If you put the `peel` command on your path from Settings, remove that link too. Homebrew removes only the one it
made.

```bash
sudo rm -f /usr/local/bin/peel
```

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

Spend your days in VS Code, or in an editor built on it? Try [Tapetum](https://github.com/TuguiDragos/tapetum), my
free theme pack: 58 themes in 28 families, each in dark and light, with every color placed by hand and its contrast
measured on the surface it sits on. Install it from the
[Visual Studio Marketplace](https://marketplace.visualstudio.com/items?itemName=tuguidragos.tapetum) or
[Open VSX](https://open-vsx.org/extension/tuguidragos/tapetum).
