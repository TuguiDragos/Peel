# Contributing to Peel

Thank you for wanting to help.

Peel removes files from people's Macs. That one fact shapes everything below: a bug here doesn't put a wrong
number on a screen, it takes away something somebody wanted. Most of this page is about the rules that keep that
from happening, and they are not up for negotiation.

## The rule everything else serves

**Nothing of the user's is ever deleted for good.** Every removal goes to the Trash through `TrashService` and is
recorded, so History can put it back; in the app it runs inside `QuitGuard.shared.run` from its first move until History
has it, and so does a Put Back, so that quitting waits for them. No code path in Peel deletes anything of the user's,
and a change that adds one won't be accepted. What Peel deletes outright is its own: its list of refusals, when
`peel history --refused --clear` is asked to forget it, and the empty placeholder `TrashMover` makes to hold a name on a
disk that cannot rename without replacing (exFAT), when the move it was made for fails. Three things Peel starts can't
be undone by History, and each says so where the user confirms it: Homebrew's own uninstall and clean up, and resetting
an app's privacy permissions. `defaults delete` for an app's preferences runs only once their file is in the Trash, and
a reset exports the domain first, so putting the file back undoes it; putting saved settings back clears a domain only
once it has been saved as a copy of its own, and asks first. Every `brew` call runs with `HOMEBREW_NO_INSTALL_CLEANUP`,
so an upgrade never cleans up on its own, and when a `brew.env` file turns that back on (`Homebrew.overrides()`), Peel
leaves upgrades to Terminal.

## What you need

- macOS 26 or later. Peel is built with the macOS 27 SDK for macOS 26 and later, the versions every release is
  tested on by hand, so it has no code for an older macOS.
- Xcode 27 or later, with Swift 6.4.
- A team to sign with, even a free one. The project names its maintainer's team, so build with yours: add
  `DEVELOPMENT_TEAM=YOUR_TEAM_ID` to the `xcodebuild` command, or choose your team for the targets under Signing &
  Capabilities in Xcode and leave that change out of your commits. The helper accepts only an app signed by the
  same team as itself, so the app and the helper you build work together. launchd starts the helper only as the
  team named in `Support/com.tuguidragos.Peel.Helper.plist` (`SpawnConstraint`), so to install the helper you
  build, put your team there as well, again outside your commits. The package's tests need no signing.
- Nothing else. The only dependency is Apple's swift-argument-parser, which Xcode fetches.
- A Release build needs `ENABLE_POINTER_AUTHENTICATION=YES` on the `xcodebuild` command line, since only the
  command line reaches the Swift packages and every program imports them for arm64e too. `Scripts/release.sh`
  passes it; a Debug build needs nothing.

```bash
xcodebuild -project Peel.xcodeproj -scheme Peel -configuration Debug -derivedDataPath build/DerivedData DEVELOPMENT_TEAM=YOUR_TEAM_ID build
```

```bash
swift test --package-path Packages/PeelCore
```

Build and test after every change, not only at the end. After a Debug build, run
`python3 Scripts/sync_localizations.py` so the string catalogs match the strings in the code. It refuses to run
without build output rather than empty the catalogs. After changing a command of `peel`, run
`python3 Scripts/generate_manual.py` as well, which writes its manual page, `Support/peel.1`, from the tool just
built.

The project's targets build with warnings as errors, and that is the bar a change has to clear. The package's
manifest doesn't set it, so ask for it on the command line to hold the package to the same bar:

```bash
swift build --package-path Packages/PeelCore -Xswiftc -warnings-as-errors
```

Tests run through the code Peel runs, on the Mac running them: a scan asks this Mac's Launch Services and reads its
system apps and a real disk, since an answer about Homebrew, launchd, Launch Services, or the disk is worth little
against a mock. A stand-in is only for what a Mac can't do on demand, such as a folder that never answers, and the
files a test scans sit in a temporary home, never in yours. When a test expects Peel to select an app's files, the
app it scans is a made-up one, under a domain kept for examples (such as `net.example`): a real app may be installed
anywhere on the Mac running the test, and another copy of it keeps those files. Some tests read this Mac on purpose,
so they are slower and depend on what you have installed. The slowest scans every app installed here, in full, to
check that nothing Peel would select is refused or shared. It takes minutes, so it runs only when asked for, and it
is worth running before a release:

```bash
PEEL_TEST_THIS_MAC=1 swift test --package-path Packages/PeelCore --filter SuggestedSelectionOnThisMacTests
```

Before a release, run Xcode's accessibility audit on every page, About, Settings, and the menu bar panel, in the
light appearance and the dark one. It moves the pointer, types, and quits a Peel that is open, so it has a scheme
of its own and runs only when asked for, on a Mac nobody is using. macOS asks once to give the test runner
Accessibility, and for an administrator's password when Automation Mode turns on. Each result comes with a picture
of the screen, in the test report:

```bash
xcodebuild test -project Peel.xcodeproj -scheme PeelUITests -derivedDataPath build/DerivedData DEVELOPMENT_TEAM=YOUR_TEAM_ID
```

[ARCHITECTURE.md](ARCHITECTURE.md) explains how the parts fit together.

## Where things live

- `Peel/`: the SwiftUI app, with its pages (`Views/`), their models (`Model/`), navigation, and the licenses it ships.
- `PeelHelper/`: the privileged helper. Read its section below before touching it.
- `PeelFinder/`: the sandboxed Finder Sync extension.
- `PeelCLI/`: the `peel` command line tool, a thin entry point.
- `PeelUITests/`: the accessibility audit, run by hand before a release.
- `Packages/PeelCore/`: everything that decides and acts, with the tests. `PeelCore` scans, matches, and removes;
  `PeelPrivileged` is the part the helper shares; `PeelCommandLine` holds the `peel` commands; `PeelLink` is the
  `peel://open` link the Finder extension sends and the app reads.
- `Localization/`: every translation, and nothing else: the string catalogs of the app and the Finder extension.
- `Support/`: the Info.plists, the helper's launchd property list, and the manual page of `peel`.
- `Logo/`: the only source of the logo: the app icon (`Peel.icon`), the menu bar glyph, and `export.sh`, which
  renders the PNGs the README shows.
- `Scripts/`: `sync_localizations.py`, which keeps the catalogs in step with the code, `generate_manual.py`,
  which keeps the manual page in step with `peel`, `release.sh`, which builds, signs, notarizes, and checks a
  release, and `make_dmg.sh`, which lays out the disk image's window with dmgbuild (run by uv) over the background
  `dmg_background.swift` draws.
- `readme-assets/`: the screenshots the README shows.
- `.github/`: the test workflow, the issue forms, and the pull request template.

## The rules a change must not break

Tests enforce these. If your change makes one of them fail, the rule is right and the change is wrong.

- **`RemovalGuard` refuses what nothing can bring back**, in every account on the Mac:
  - iCloud Drive and other cloud storage folders, and the Trash itself;
  - keychains, `~/.ssh`, `~/.gnupg`, `~/.aws`, `~/.password-store`, the signing keys and credentials that
    `ProtectedData.homeKeys` names one by one, and the wallet keys that `ProtectedData.walletKeys` names, each
    read from the wallet's own documentation or source;
  - a browser profile that holds a wallet extension's vault or Brave's own wallet, and a folder holding one a
    level or two down (`ProtectedData.holdsABrowserWallet`);
  - Mail, Messages, Safari, Contacts, Calendars, Reminders, Shortcuts, HomeKit, Accounts, Finance,
    IdentityServices, FaceTime and call history, Freeform, Journal, Stickies, the passes in Wallet, and every
    group container of Apple's own, where macOS keeps notes and other data;
  - `Autosave Information`, where apps keep work not saved yet;
  - the spelling and text replacement stores, and iPhone and iPad backups;
  - photo, music, and video libraries, and a folder holding one a level or two down;
  - a sandboxed app's `Documents`, and its container while that folder holds anything or cannot be read;
  - the folders every account starts with (Desktop, Documents, Downloads, Movies, Music, Pictures, Public)
    themselves, though not what is inside them;
  - work a tool keeps in a cache folder (an IDE's local history, Deno's `location_data`), and the global
    preferences files.

  It judges the item, not how its path is spelled: each rule is asked of the path as written, as found on disk,
  and as the kernel names the item, so another case, a link, or a `/.vol` name reaches the same answer. The
  places it protects by path (in the home, the keychains, and the folders that stay themselves) are known by
  device and inode as well, wherever a link leads them, and are found without opening them
  (`PathPattern.locatedWithoutOpening`): opening a folder inside another app's container makes macOS ask the
  person for that app's data. [SAFETY.md](SAFETY.md) lists every protected place.
- **Paths are compared name by name, never as text.** A Swift `String` reads a slash and a combining mark after
  it as one `Character`, so `hasPrefix(folder + "/")` and `split(separator: "/")` miss a folder that such a name
  sits in. Every "is this inside that folder" question goes through `PathComponents`.
- **Only `certain` and `likely` matches that no other installed app claims are selected for the user.**
  Anything shared is shown and left unselected, and nothing is selected for an app that would stay.
- **What may exist nowhere else is never selected for the user.** A folder with a wallet, a signing key, or a
  repository inside, or one Peel could not finish reading, is shown with its reason and moves only when the user
  selects it: Select All, `peel uninstall`, `peel orphans --remove`, and `peel projects --remove` pass it by. The
  one exception is a repository inside a folder its tool tags as a cache (`CACHEDIR.TAG`), such as Swift Package
  Manager's `.build`, whose clones the tool makes again.
- **The user's exclusions reach every scanner**, so an excluded item never appears in the first place.
- **Resetting an app clears its settings, never the app.** It takes the app's own data only when the user
  selects it, needs the app to be quit, and inside a sandboxed app's container never touches `Documents`,
  `Application Support`, or `Autosave Information`.
- **A Homebrew cask counts as evidence only when it is proved**, by naming the app bundle, the identifier it
  quits, or an installer receipt that is on this Mac. A guessed name is never believed on its own.
- **Duplicates always keep at least one copy**, and refuse a file that changed since the scan.

## Changes that need a particular test

- **Matching**: `LeftoverMatcherTests`. A new rule needs the case it catches and a case it must not catch.
- **A wallet extension**: its ID goes into `BrowserWallets.swift` only in the comment above its SHA-256, never as
  text the compiler keeps. XProtect, the malware scanner in macOS, takes a binary that carries a few wallet IDs for
  a program that steals them and moves it to the Trash, a test binary included, so tests read the IDs from those
  comments (`WalletIDs`). `BrowserWalletTests` checks every fingerprint against the ID above it.
- **The privileged helper**: `PrivilegedPathPolicyTests`, and for any change to the helper a bump of
  `HelperIdentity.protocolVersion`.
- **`DeveloperCaches.definitions`**: a source showing the folder is a cache, and a `DeveloperCachesTests` run.
  Never a toolchain, never an installation, never a file holding an account or a token, and never a path inside
  another path already in the table.
- **Anything that decides what may be removed**: a test that fails without your fix, written to get past the
  rule rather than to confirm it. The `Attack*Tests` files hold these.

## The privileged helper

`PeelHelper` runs as root. Treat every argument it receives as hostile, even from Peel: the app is a program on a
disk that somebody may have replaced.

- It has no shell, accepts no path outside the folders it serves, and refuses whenever it is unsure.
- It answers administrators only, asked when a connection opens and again with each message. The account is the
  connection's and says nothing about which process sent a message (`xpc_connection_create(3)`), so no rule may
  rest on it for that.
- It accepts only a copy of Peel signed by the same team, checked when a connection opens and for every message
  after it (`setCodeSigningRequirement` on each accepted connection), and a released helper refuses a build that
  can be debugged.
- It never uses a path again after checking it. It holds the folder open and works through that descriptor, so
  a folder swapped after the check leads nowhere.
- A new operation needs `PrivilegedPathPolicyTests`, and any change to the helper a protocol version bump,
  which asks every user to install the helper again. That cost is deliberate.

If you are unsure whether something belongs in the helper, it doesn't. The helper should stay small enough to
read in one sitting.

## Style

- Small, focused files, and code that reads like the code around it.
- **Few comments, written for people.** Say what the code can't: what a declaration is for, why a rule exists,
  and which documented behavior of macOS forced a workaround, with its public source (a man page, an SDK header,
  Apple's documentation). No history and no lab notes: a fixed bug belongs in the commit message, and the comment
  keeps only the rule it left. Don't narrate what the next line does, and keep lines within 120 columns.
- **No dead code.** Whatever your change leaves unused (a function, a type, a string, a file, a test helper)
  goes in the same change.
- **One English: American**, as the Apple Style Guide writes it: color, catalog, license, canceled, and the
  serial comma. A checkbox is selected or deselected, never ticked.
- **No em or en dashes**, in the interface, in comments, or in documents, and no spaced hyphen standing in for
  one. A colon, a comma, or parentheses say the same thing, and a range reads "3 to 4". Interface text writes the
  curly apostrophe (’), as macOS does, and a translation the marks macOS writes in its language: Dutch keeps the
  straight apostrophe, as Apple's Dutch does. The `peel` tool writes its own words in plain ASCII, and names,
  paths, and macOS's own error messages as they are, in UTF-8, with what could hide or reorder text shown as `?`.
- **Every translation lives in `Localization/`.** Peel is translated into 17 languages, in the words macOS itself
  uses in each. Write new or changed interface text in English, and run `python3 Scripts/sync_localizations.py`
  after a Debug build so the catalog lists it. The translations are added before your change is merged; until
  then `StringCatalogTests` fails for that text, and only for it. The `peel` tool and PeelCore stay in English.
- **Rows of a long list stay cheap to build.** A list builds its rows as they scroll into view. A checkbox in a row
  is `NativeCheckbox` beside the item, with `checkboxTitleLine()` on the first line of its title and
  `checkboxTitle()` on the title, rather than a checkbox `Toggle` whose label is the row, since SwiftUI asks a
  `Toggle`'s button for its size each time the row is measured. A button in each row takes `RowButtonStyle` or
  `.borderless`: one of another style changes the window's list of focusable views whenever a row scrolls in or out.
  A row a `ForEach` repeats never hides its own separator and is never a `Toggle` itself; the `ForEach` hides the
  separators. A row that stands alone, such as a header or a notice, may hide its own, which costs nothing.
- **The interface follows Liquid Glass.** The sticker album look belongs to Home, the menu bar panel, and About
  only; every other screen reads as macOS (system type, `Form` and `Section`, native controls). Icons are SF
  Symbols, and the logo comes only from `Logo/`, but for the face at the head of the sidebar, which draws the logo's
  shape in code so it can move (`Face` in `PeelFace.swift`) and peels it less on purpose, so its eyes have room: a
  change to the logo's shape changes those numbers too.

## Proposing a change

1. Open an issue first for anything beyond a small fix, so nobody writes something that won't be taken.
2. One change per pull request, with a description of what goes wrong without it.
3. Say how you tested it. "Tests pass" isn't that; "this test failed before the change and passes after, and I
   checked it on a real install of X" is.
4. If you found the behavior in Apple's documentation or a man page, quote it. Peel's decisions are meant to be
   traceable to something outside itself.

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
ever be relicensed out from under you.
