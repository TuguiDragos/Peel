# Contributing to Peel

Thank you for wanting to help.

> **Working with a coding assistant?** Give it [AGENTS.md](AGENTS.md) before the first change, and have it work by
> those rules. Many assistants read that file by themselves. The rules bind every change, with an assistant or
> without, so read it yourself too.

Peel removes files from people's Macs. That one fact shapes everything here: a bug doesn't put a wrong number on a
screen; it takes away something somebody wanted. So every problem is proved before anything changes, a test fails
before the fix is written, and the result is checked where it shows, as [AGENTS.md](AGENTS.md) describes step by step.

## What you need

- macOS 26 or later. Peel is built with the macOS 27 SDK for macOS 26 and later, the versions every release is
  tested on by hand, so it has no code for an older macOS.
- Xcode 27 or later, with Swift 6.4.
- A team to sign with, even a free one. The project names its maintainer's team, so build with yours: add
  `DEVELOPMENT_TEAM=YOUR_TEAM_ID` to the `xcodebuild` command, or choose your team under Signing & Capabilities for each
  of the four targets the Peel scheme builds (and PeelTests and PeelUITests, to run the app's own tests and the audit),
  and leave that change out of your commits. launchd starts the helper only as the team named in
  `Support/com.tuguidragos.Peel.Helper.plist` (`SpawnConstraint`), so to install the helper you build, put your team
  there as well, again outside your commits. The package's tests need no signing.
- Two dependencies: Apple's swift-argument-parser, which Xcode fetches, and Sparkle, which updates Peel. Sparkle is
  built from its source, at the commit `Scripts/build_sparkle.sh` names, with arm64e and without its XPC services: run
  the script once before the first build. When that commit changes, move `build/SparkleSource` to the Trash first, since
  the script refuses a checkout at any other commit, then run it again.

```bash
zsh Scripts/build_sparkle.sh
xcodebuild -project Peel.xcodeproj -scheme Peel -configuration Debug -destination "platform=macOS,arch=$(uname -m)" \
  -derivedDataPath build/DerivedData DEVELOPMENT_TEAM=YOUR_TEAM_ID build
```

```bash
swift test --package-path Packages/PeelCore -Xswiftc -warnings-as-errors
```

The app's own models are tested inside Peel, which the PeelTests scheme launches with `PEEL_HOSTS_TESTS` set, so that
it starts nothing and shows nothing:

```bash
xcodebuild -project Peel.xcodeproj -scheme PeelTests -configuration Debug \
  -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath build/DerivedData DEVELOPMENT_TEAM=YOUR_TEAM_ID test
```

Build and test after every change, not only at the end. After a Debug build, run
`python3 Scripts/sync_localizations.py` so the string catalogs match the strings in the code; it refuses to run
without build output, or with a build older than the code, rather than empty the catalogs, and `--check` says what
would change without writing anything. After changing anything `peel` says about itself (a command, an option, or a
line of its help), run `python3 Scripts/generate_manual.py`, which writes its manual page, `Support/peel.1`, from the
tool just built. Both scripts read the Debug build in `build/DerivedData`, which the command above makes; a build
from Xcode's Product menu goes elsewhere.

Before you propose a change, run what the Checks workflow runs as well. A Release build needs
`ENABLE_POINTER_AUTHENTICATION=YES` and `MACOSX_DEPLOYMENT_TARGET=26.0` on the `xcodebuild` command line, since only
the command line reaches the Swift packages (`Scripts/release.sh` passes both), and some of Swift's checks run only
on optimized code:

```bash
xcodebuild -project Peel.xcodeproj -scheme Peel -configuration Release -destination 'generic/platform=macOS' \
  -derivedDataPath build/ReleaseCheck CODE_SIGNING_ALLOWED=NO ENABLE_POINTER_AUTHENTICATION=YES \
  MACOSX_DEPLOYMENT_TARGET=26.0 build
xcodebuild -project Peel.xcodeproj -scheme PeelUITests -configuration Debug \
  -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath build/DerivedData DEVELOPMENT_TEAM=YOUR_TEAM_ID \
  build-for-testing
python3 Scripts/sync_localizations.py --check
python3 Scripts/generate_manual.py --check
```

## Where things live

- `Peel/`: the SwiftUI app, with its pages (`Views/`) and their models (`Model/`).
- `PeelHelper/`: the privileged helper, which runs as root. Read its rules in [AGENTS.md](AGENTS.md) before
  touching it.
- `PeelFinder/`: the sandboxed Finder Sync extension.
- `PeelCLI/`: the `peel` command-line tool, a thin entry point.
- `PeelTests/`: the tests of the app's own models, run inside Peel.
- `PeelUITests/`: the accessibility audit, run by hand before a release.
- `Packages/PeelCore/`: everything that decides and acts, with the tests. `PeelCore` scans, matches, and removes;
  `PeelPrivileged` is the part the helper shares; `PeelCommandLine` holds the `peel` commands; `PeelLink` is the
  `peel://open` link the Finder extension sends and the app reads.
- `Localization/`: every translation, and nothing else.
- `Support/`: the Info.plists, the helper's launchd property list, and the manual page of `peel`.
- `Logo/`: the only source of the logo: the app icon (`Peel.icon`), the glyph for the menu bar and the Finder menu
  (`Logo.xcassets`), and `export.sh`, which renders it as a light picture and the dark one the README shows.
- `Scripts/`: the scripts that build Sparkle, keep the catalogs and the manual page in step with the code, and make
  and check a release.
- `Terminal/`: the Terminal themes and the pictures TERMINAL.md shows.
- `readme-assets/`: the screenshots and pictures the documents show.
- `.github/`: the Checks workflow, Dependabot's settings, the issue and discussion forms, the pull request template,
  and the sponsor link in FUNDING.yml.
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
- **Only what is the app's alone, by its identifier or its name, is selected for the user.** A match Peel is unsure
  of, anything another installed app shares, and anything that may exist nowhere else is shown with its reason and
  left to the user.
- **Prove the problem on a real Mac before changing anything**, write a test that fails first, fix the cause, and
  check the result where it shows.
- **Tests run as Peel runs**, on the real Mac, with made-up apps and a temporary home, never your own files.
- **A fix is for every macOS; a visual change is for macOS 27 alone.** A bug is fixed for macOS 26 and 27 alike, and
  so is a visual bug whose cause holds on both, while any other change to how Peel looks goes in the macOS 27 branch
  and leaves macOS 26's code as it is.
- **Every translation lives in `Localization/`**, in the words macOS itself uses in each language.
- **Few comments, lines within 120 columns, American English, no em or en dashes, and no dead code.**

## Proposing a change

1. For anything beyond a small fix, ask first, so nobody writes something that won't be taken: report a problem
   with the bug report form, or describe an idea in Discussions, under Ideas.
2. One change per pull request, with a description of what goes wrong without it.
3. Say how you tested it. "Tests pass" isn't that; "this test failed before the change and passes after, and I
   checked it on a real install of X" is.
4. If something couldn't be checked on your Mac, say what and why, and the maintainer will check it.
5. If you found the behavior in Apple's documentation or a man page, quote it. Peel's decisions are meant to be
   traceable to something outside itself.
6. If an assistant helped, say so in the pull request, and exactly how: what it wrote, what it reviewed, what it
   translated, and what you checked yourself. If none did, there is nothing to say.

## Reporting a security problem

Please don't open an issue, a discussion, or a pull request for it. [SECURITY.md](SECURITY.md) says how to report
it privately.

## Code of conduct

Everyone taking part is expected to follow the [Code of Conduct](CODE_OF_CONDUCT.md).

## Licensing of contributions

Peel is free software under the GNU General Public License, version 3 or later, and it will stay free. It isn't
sold and has no paid edition, so there is no separate commercial license for your work to be folded into.

What you contribute is under the same license as the rest of Peel, as [GitHub's Terms of
Service](https://docs.github.com/en/site-policy/github-terms/github-terms-of-service#6-contributions-under-repository-license)
say for any repository with a license, and you are saying it is yours to give. There is no copyright assignment and
no agreement to sign, because nothing here will ever be relicensed out from under you.
