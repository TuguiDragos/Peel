# Contributing to Peel

Thank you for wanting to help.

> **Working with a coding assistant?** Give it [AGENTS.md](AGENTS.md) before the first change, and have it work by
> those rules. Many assistants read that file by themselves. The rules bind every change, with an assistant or
> without, so read it yourself too.

Peel removes files from people's Macs. That one fact shapes everything here: a bug doesn't put a wrong number on a
screen, it takes away something somebody wanted. So every change is proved before it is made, tested before it is
fixed, and checked where it shows, as [AGENTS.md](AGENTS.md) describes step by step.

## What you need

- macOS 26 or later. Peel is built with the macOS 27 SDK for macOS 26 and later, the versions every release is
  tested on by hand, so it has no code for an older macOS.
- Xcode 27 or later, with Swift 6.4.
- A team to sign with, even a free one. The project names its maintainer's team, so build with yours: add
  `DEVELOPMENT_TEAM=YOUR_TEAM_ID` to the `xcodebuild` command, or choose your team under Signing & Capabilities in
  Xcode, and leave that change out of your commits. launchd starts the helper only as the team named in
  `Support/com.tuguidragos.Peel.Helper.plist` (`SpawnConstraint`), so to install the helper you build, put your team
  there as well, again outside your commits. The package's tests need no signing.
- Nothing else. The only dependency is Apple's swift-argument-parser, which Xcode fetches.

```bash
xcodebuild -project Peel.xcodeproj -scheme Peel -configuration Debug -derivedDataPath build/DerivedData DEVELOPMENT_TEAM=YOUR_TEAM_ID build
```

```bash
swift test --package-path Packages/PeelCore -Xswiftc -warnings-as-errors
```

Build and test after every change, not only at the end. After a Debug build, run
`python3 Scripts/sync_localizations.py` so the string catalogs match the strings in the code; it refuses to run
without build output rather than empty the catalogs. After changing a command of `peel`, run
`python3 Scripts/generate_manual.py`, which writes its manual page, `Support/peel.1`, from the tool just built.

A Release build needs `ENABLE_POINTER_AUTHENTICATION=YES` and `MACOSX_DEPLOYMENT_TARGET=26.0` on the `xcodebuild`
command line, since only the command line reaches the Swift packages; `Scripts/release.sh` passes both.

## Where things live

- `Peel/`: the SwiftUI app, with its pages (`Views/`) and their models (`Model/`).
- `PeelHelper/`: the privileged helper, which runs as root. Read its rules in [AGENTS.md](AGENTS.md) before
  touching it.
- `PeelFinder/`: the sandboxed Finder Sync extension.
- `PeelCLI/`: the `peel` command line tool, a thin entry point.
- `PeelUITests/`: the accessibility audit, run by hand before a release.
- `Packages/PeelCore/`: everything that decides and acts, with the tests. `PeelCore` scans, matches, and removes;
  `PeelPrivileged` is the part the helper shares; `PeelCommandLine` holds the `peel` commands; `PeelLink` is the
  `peel://open` link the Finder extension sends and the app reads.
- `Localization/`: every translation, and nothing else.
- `Support/`: the Info.plists, the helper's launchd property list, and the manual page of `peel`.
- `Logo/`: the only source of the logo, the app icon and the menu bar glyph.
- `Scripts/`: the scripts that keep the catalogs and the manual page in step with the code, and build a release.
- `Terminal/`: the Terminal themes and the pictures TERMINAL.md shows.
- `readme-assets/`: the screenshots the documents show.
- `.github/`: the Checks workflow, the issue forms, and the pull request template.
- `docs/`: Peel's website, peel.tuguidragos.com.
- The documents, at the root: [README.md](README.md) says what Peel is and how to get it, [GUIDE.md](GUIDE.md) what
  each tool does, [PRIVACY.md](PRIVACY.md) what Peel sends, [SAFETY.md](SAFETY.md) what it protects,
  [TERMINAL.md](TERMINAL.md) every Terminal theme and setting, [SECURITY.md](SECURITY.md) how to report a
  vulnerability, and [CHANGELOG.md](CHANGELOG.md) what each release changed. [ARCHITECTURE.md](ARCHITECTURE.md)
  explains how the parts fit together, and [AGENTS.md](AGENTS.md) holds the rules.

## The rules, in short

[AGENTS.md](AGENTS.md) has each of them in full, and tests enforce most. If a change makes one fail, the rule is
right and the change is wrong.

- **Nothing of the user's is ever deleted for good.** Every removal goes to the Trash through `TrashService` and is
  recorded, so History can put it back.
- **What nothing could bring back is refused**, whoever asks: keychains, crypto wallets, Mail, Messages, photo
  libraries, and the rest [SAFETY.md](SAFETY.md) lists.
- **Only what is certainly an app's, and no other app's, is selected for the user.** Anything shared, guessed, or
  possibly kept nowhere else is shown with its reason and left to the user.
- **Prove the problem on a real Mac before changing anything**, write a test that fails first, fix the cause, and
  check the result where it shows.
- **Tests run as Peel runs**, on the real Mac, with made-up apps and a temporary home, never your own files.
- **A fix is for every macOS; a visual change is for macOS 27 alone.** A bug is fixed for macOS 26 and 27 alike,
  while a change to how Peel looks goes in the macOS 27 branch and leaves macOS 26's code as it is.
- **Every translation lives in `Localization/`**, in the words macOS itself uses in each language.
- **Few comments, lines within 120 columns, American English, no em or en dashes, and no dead code.**

## Proposing a change

1. Open an issue first for anything beyond a small fix, so nobody writes something that won't be taken.
2. One change per pull request, with a description of what goes wrong without it.
3. Say how you tested it. "Tests pass" isn't that; "this test failed before the change and passes after, and I
   checked it on a real install of X" is.
4. If something couldn't be checked on your Mac, say what and why, and the maintainer will check it.
5. If you found the behavior in Apple's documentation or a man page, quote it. Peel's decisions are meant to be
   traceable to something outside itself.
6. If an assistant helped, say so in the pull request, and exactly how: what it wrote, what it reviewed, what it
   translated, and what you checked yourself. If none did, there is nothing to say.

## Reporting a security problem

Please don't open an issue. [SECURITY.md](SECURITY.md) says how to report it privately.

## Code of conduct

Everyone taking part is expected to follow the [Code of Conduct](CODE_OF_CONDUCT.md).

## Licensing of contributions

Peel is free software under the GNU General Public License, version 3 or later, and it will stay free. It isn't
sold and has no paid edition, so there is no separate commercial license for your work to be folded into.

Sign off your commits with `git commit -s`. That is the [Developer Certificate of
Origin](https://developercertificate.org/): you are saying the contribution is yours to give, under the same
license as the rest of Peel. There is no copyright assignment and no agreement to sign, because nothing here will
ever be relicensed out from under you. The Checks workflow checks every commit of a pull request for a sign-off by
its author.
