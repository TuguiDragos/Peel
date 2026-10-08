# Working on Peel

This file holds the rules every change to Peel follows. It is written for coding assistants, which read it before
they start, and it binds the person directing one just the same: the rules don't change with who, or what, writes
the code. [CONTRIBUTING.md](CONTRIBUTING.md) says how to propose a change, [ARCHITECTURE.md](ARCHITECTURE.md) how
the parts fit together, and [SAFETY.md](SAFETY.md) what Peel protects.

Peel removes files from people's Macs. A bug here doesn't put a wrong number on a screen: it takes away something
somebody wanted. That is why the rules are strict, and why none of them is a matter of taste.

## How every change is made

Never change anything blindly. Every change goes through these steps, in this order, however small it looks: search,
prove, and only then fix.

1. **Search.** Read the code as it is now, and every caller and reader of what the change touches: the app, the
   `peel` command, the helper, and the tests. Read the current official documentation for every fact the change
   relies on: Apple's documentation, the SDK's headers (`xcrun --show-sdk-path`), the man page on this Mac, or the
   tool's own source at a named commit. Never work from memory: an API you remember may have changed.
2. **Prove the problem before changing anything.** Show on a real Mac that it happens, and why: a measurement, a
   probe that is thrown away afterwards, the app showing it, or a test that fails for the reason given. A
   suspicion that can't be proved is reported as one, and nothing changes for it.
3. **Write the test first.** It fails without the change, for the reason the change gives, and passes with it.
   Check that it really catches the problem: put the old code back, watch it fail, and restore the fix. If it
   still passes, first make sure the old code really went back, then look for another layer that stops the problem
   before it, and give each layer a test of its own.
4. **Fix the cause**, in the type or the rule where the fact belongs. No workaround, no special case keyed by a
   name, no table on the side. A defect found on the way is fixed the same way, with its own test.
5. **Follow the change along its whole path**, from where it starts to where it shows, and check every step of it
   carefully. Find every function the change touches and every function that touches what it changed: callers,
   readers, overrides, observers, the app, `peel`, the helper, and the tests. Check that none of them works worse
   because of the change, and follow each one you find the same way, along its own path, until nothing that depends
   on the change is left unchecked.
6. **Build and test after every change**, not only at the end: the whole package suite with warnings as errors,
   and the app's Debug build ([CONTRIBUTING.md](CONTRIBUTING.md#what-you-need) has the commands).
7. **Check it where it shows**, live: open the page the change touches, or run the `peel` command it changes, and
   see the result. Never on anyone's real files: tests use a temporary home, and a check that moves files runs on
   a disk image made for it.
8. **Leave nothing behind**: no probe, no debugging output, and nothing the change left unused.
9. **Say exactly what happened.** Report a failing test with its output, a step you skipped as skipped, and what
   you couldn't prove as unproved. If something can't be checked on your Mac, say what and why in the pull
   request, and the maintainer will check it.

**When you're stuck, read before you try.** Don't guess at how macOS, Swift, or a tool behaves, and don't change
Peel's code to see whether something helps. Read the current official documentation for the version Peel runs on:
Apple's documentation and release notes, the SDK's headers, the man page on this Mac, or the tool's own source at a
named commit. Rely on what the source itself says, never on a summary of it, and prove it on a Mac with a probe
before a fix rests on it.

A choice about what Peel does for people, what it selects, what it says, or how it looks, is the maintainer's.
Propose it with your reasons; don't make it on the way.

## What must never break

Tests enforce these rules. If a change makes one of them fail, the rule is right and the change is wrong.

- **Nothing of the user's is ever deleted for good.** Every removal goes to the Trash through `TrashService` and is
  recorded, so History can put it back. In the app it runs inside `QuitGuard.shared.run` from its first move until
  History has it, and so does a Put Back, so quitting waits for them. Peel deletes outright only what holds nothing of
  the user's: the empty placeholder `TrashMover` makes to hold a name on a disk that can't rename without replacing
  (exFAT), when the move it was made for fails, the folder `PreferenceBackup` makes for a reset's saved settings, when
  saving fails while it is still empty, and the empty file cfprefsd writes back where a moved settings file was when
  `PreferenceCleanup` forgets a domain it still holds. Its list of refusals goes to the Trash when
  `peel history --refused --clear` asks.
- **What History can't undo says so where the person confirms it**: Homebrew's own uninstall and clean up,
  resetting an app's privacy permissions, and Force Quit for an app that is still open 10 seconds after Peel asked
  it to quit. `defaults delete` for an app's preferences runs only once their file is in the Trash, and a reset
  exports the domain first, so putting the file back undoes it; putting saved settings back clears a domain only
  once it has been saved as a copy of its own, and asks first. Every `brew` call runs with
  `HOMEBREW_NO_INSTALL_CLEANUP`, so an upgrade never cleans up on its own, and when a `brew.env` file turns that back
  on (`Homebrew.overrides()`), Peel leaves upgrades to Terminal.
- **`RemovalGuard` refuses what nothing can bring back**, in every account on the Mac: iCloud Drive and other cloud
  storage, the Trash itself, keychains and the keys and credentials `ProtectedData.homeKeys` names, the wallet keys
  `ProtectedData.walletKeys` names, a browser profile holding a wallet extension's vault, Mail, Messages, Safari,
  Contacts, Calendars and Apple's other stores of personal data, every group container of Apple's own, work not
  saved yet, photo, music, and video libraries, a sandboxed app's `Documents`, the folders every account starts
  with, and work a tool keeps only in a cache folder. [SAFETY.md](SAFETY.md) lists every place. The guard judges the
  item, not how its path is spelled: each rule is asked of the path as written, as found on disk, and as the kernel
  names the item, and the places it protects are known by device and inode too.
- **Paths are compared name by name, never as text.** A Swift `String` reads a slash and a combining mark after it
  as one `Character`, so `hasPrefix(folder + "/")` and `split(separator: "/")` miss a folder such a name sits in.
  Every "is this inside that folder" question goes through `PathComponents`.
- **Only `certain` and `likely` matches that no other installed app claims are selected for the user.** Anything
  shared is shown and left unselected, and nothing is selected for an app that would stay.
- **What may exist nowhere else is never selected for the user.** A folder with a wallet, a signing key, a password
  database, or a repository inside, one where an app keeps what may exist only on this Mac, or one Peel couldn't
  finish reading, is shown with its reason and moves only when the user selects it. `peel uninstall`, `peel orphans
  --remove`, and `peel projects --remove` pass it by, and Select All takes it only once the user has answered the
  question that counts what Peel doesn't recommend (`SelectableRows.notRecommendedAdded`). A repository can still be
  selected in two places, since its tool clones it again: inside a folder its tool tags as a cache
  (`CACHEDIR.TAG`), such as Swift Package Manager's `.build`, and inside a cache on the Developer page.
- **The user's exclusions reach every scanner**, so an excluded item never appears in the first place.
- **Resetting an app clears its settings, never the app.** It takes the app's own data only when the user selects
  it, needs the app to be quit, and inside a sandboxed app's container never touches `Documents`,
  `Application Support`, or `Autosave Information`.
- **A Homebrew cask counts as evidence only when it is proved**, by naming the app bundle, the identifier it quits,
  or an installer receipt that is on this Mac. A guessed name is never believed on its own.
- **Duplicates always keep at least one copy**, and refuse a file that changed since the scan.
- **An update check sends no more than [PRIVACY.md](PRIVACY.md) says.** A feed request carries Peel's name and no
  language, a redirect is followed only to https, the session keeps no cache or cookie a server could read back,
  and Apple is asked only about an app bought from the App Store (`UpdatePrivacyTests`).
- **No code reads macOS's privacy database.** What macOS records about privacy is not API, and from macOS 27 apps
  can't read it, so App Management is learned from what a removal shows, on every macOS (`PrivateDatabaseTests`).

## The privileged helper

`PeelHelper` runs as root. Treat every argument it receives as hostile, even from Peel: the app is a program on a
disk that somebody may have replaced.

- It has no shell, accepts no path outside the folders it serves, and refuses whenever it is unsure.
- It answers administrators only, asked when a connection opens and again with each message. The account is the
  connection's and says nothing about which process sent a message (`xpc_connection_create(3)`), so no rule may rest
  on it for that.
- It accepts only a copy of Peel signed by the same team and no older a build than itself, checked when a connection
  opens and for every message after it, and a released helper refuses a build that can be debugged.
- It never uses a path again after checking it: it opens the folder, checks the item there as the kernel names the
  folder (`F_GETPATH`), works only through that descriptor, and moves the item only while its identity is the one
  it checked, so a folder or an item swapped after the check leads nowhere.
- A new operation needs `PrivilegedPathPolicyTests`, and any change to the helper a bump of
  `HelperIdentity.protocolVersion`, so Peel never works with a helper of another version.
- The helper's identifier and its launchd property list stay the same from one version to the next. Updates rely on
  it: launchd starts the new helper by itself, and a version that changed either would have to register it again.

If you are unsure whether something belongs in the helper, it doesn't.

## Tests

- **Tests run as Peel runs, on the Mac running them**: the real Launch Services, the real system apps, the real
  disk. Nothing (a flag, a default, an environment variable) makes a test skip what Peel does. A stand-in is only
  for what a Mac can't do on demand, such as a folder that never answers.
- **A test that fails now and then has a cause.** Run the whole suite again and again until it fails, find what
  differed, and fix that. Never run it again until it passes, and never widen a timeout to hide it.
- **Never bound a test by the clock.** In a full run a short sleep or a timer can resume seconds late, so a test
  waits for the thing it measures (a program's end, a file's change), and work it waits on runs at user-initiated
  priority rather than the default.
- The files a test scans sit in a temporary home, never in yours, and nothing is registered with Launch Services
  from a test. An app a test expects Peel to act on is a made-up one, named under a domain kept for examples
  (`org.example`, `com.example`, `net.example`). A program a test starts from a folder of its own is a copy of
  `/bin/sleep` signed ad hoc (`TemporaryDirectory.runningProgram`): macOS kills a plain copy of one of its own
  programs started from anywhere else, usually within a second, for breaking its launch constraints. A folder a
  test makes never ends in a package's extension: `org.example.App` is an app to macOS and to Peel, so nothing
  inside it is looked at as a folder's contents.
- Some changes need a particular test:
  - matching: `LeftoverMatcherTests`, with the case the rule catches and a case it must not catch;
  - anything that decides what may be removed: a test that fails without the fix, written to get past the rule
    rather than to confirm it (the `Attack*Tests` files);
  - a wallet extension: its ID goes into `BrowserWallets.swift` only in the comment above its SHA-256, never as text
    the compiler keeps, because XProtect takes a binary carrying a few wallet IDs for a program that steals them;
    `BrowserWalletTests` checks every fingerprint against the ID above it;
  - a developer cache in `DeveloperCaches.definitions`: a source showing the folder is a cache, a link into a
    repository naming a commit and not a branch, and a `DeveloperCachesTests` run. Never a toolchain, an
    installation, or a file holding an account or a token;
  - anything a document names or counts: the document changes in the same change. `DocumentationTests` looks in the
    code for every name a document writes in code font, `TerminalThemeTests` in TERMINAL.md for every line the
    Terminal page writes, `CommandLineTests` in `Support/peel.1` for every command of `peel`, and
    `DesktopWalletTests` checks SAFETY.md's count of wallet places.
- Slower checks run only when asked for, and both are worth running before a release:
  `PEEL_TEST_THIS_MAC=1 swift test --package-path Packages/PeelCore --filter SuggestedSelectionOnThisMacTests`
  scans every app installed on the Mac and checks that nothing Peel would select is refused or shared, and the
  `PeelUITests` scheme runs Xcode's accessibility audit on every page, in light and dark, moving the pointer and
  typing, so it runs on a Mac nobody is using:
  `xcodebuild test -project Peel.xcodeproj -scheme PeelUITests -derivedDataPath build/DerivedData`.
- For work on Peel itself: `PEEL_SNAPSHOT=<folder>`, in a Debug build, renders Home, About, and the menu bar panel
  to PNG files in light and dark, each also with Increase Contrast, then quits; `PEEL_TERMINAL_EXPORT=<folder>`, in
  a Debug build, writes what `Terminal/` holds, then quits; `PEEL_MEASURE=<name>`, in every build, appends launch and
  frame timings to `~/Library/Logs/Peel/<name>`; and `PEEL_TEST_VOLUME=<folder>` lets the tests use the Trash of
  another volume, on a disk image made for it.

## Code

- Swift 6.4 in the Swift 6 language mode, macOS 26 and later only, with no code for an older macOS. The app runs on
  the main actor by default, and heavy work in PeelCore is `@concurrent`. The project's targets build with warnings
  as errors, and the package is held to the same bar by `-warnings-as-errors` on the command line.
- Small, focused files, and code that reads like the code around it. A dependency only when nothing else will do.
- **Few comments, written for people.** Say what the code can't: what a declaration is for, why a rule exists, and
  which documented behavior of macOS forced a workaround, with its public source. No history and no notes from a
  session: a fixed bug belongs in the commit message. Code, comments, tests, and documents speak about Peel, never
  about who or what wrote them.
- **Lines within 120 columns**, code and comments alike. A string is never split to fit: `LineLengthTests` measures
  each line of Swift without its strings.
- **No dead code.** Whatever a change leaves unused goes in the same change.

## macOS 26 and macOS 27

Peel runs on macOS 26 and later, and the two versions are treated differently in one way only.

- **A fix is for every version.** A bug in what Peel does, whether in what it finds, selects, moves, refuses, or
  says, or a crash, is fixed once for macOS 26 and 27 alike, with no `if #available`.
- **A change to how Peel looks is for macOS 27 alone.** How Peel looks and lays out on macOS 26 is settled, so a
  visual change goes in the macOS 27 branch of an `if #available(macOS 27, *)`, and the macOS 26 branch keeps exactly
  the code it had. Before committing, read the diff and confirm that no line that runs on macOS 26 changed.
- **A visual bug whose cause holds on both versions is fixed on both**, such as one that follows from a documented
  SwiftUI or AppKit rule, and the commit message says why the cause holds on both.

## The interface

- It follows Liquid Glass. The sticker album look belongs to Home, the menu bar panel, and About only; every other
  screen reads as macOS, with system type, `Form` and `Section`, and native controls. Icons are SF Symbols, and the
  logo comes only from `Logo/`, but for the face at the head of the sidebar, which draws the logo's shape in code so
  it can move (`Face` in `PeelFace.swift`): a change to the logo's shape changes those numbers too.
- Everything can be used without a pointer. VoiceOver, Voice Control, and Switch Control can press every switch,
  named by its row's title: on macOS 27 a row's switch is `RowSwitch`, whose label is empty rather than hidden,
  since a hidden label leaves AppKit's own switch outside the accessibility tree; on macOS 26 a switch whose label is
  hidden carries an `accessibilityRepresentation`. Every control is at least 20 by 20 points, and text takes the
  system's styles by role, so it follows the system's text size.
- **Words take no color of their own** outside Home, the menu bar panel, and About: orange, green, red, blue, or the
  accent color read under the 4.5:1 text needs on a light background. The color goes on a symbol beside the words,
  which keep the style of the text around them: `StatusLabel` for a warning or a state, a `Badge`'s `tint`, and a
  note's `caution`.
- Rows of a long list stay cheap to build. A checkbox in a row is `NativeCheckbox` beside the item, with
  `checkboxTitleLine()` on the first line of its title and `checkboxTitle()` on the title, rather than a checkbox
  `Toggle` whose label is the row; Duplicates' rows keep their `Toggle`, where the AppKit checkbox costs as much. A
  button in a row takes `RowButtonStyle` or `.borderless`, and the `ForEach` that repeats rows hides their
  separators, never a row its own. A `Label` beside a row's title pulls the row's separator under its own words, so
  a status or a tag sits in `LeavesRowSeparatorAlone`, as `StatusLabel` and `Badge` do.

## Words and translations

- **One English, American**, as the Apple Style Guide writes it: color, catalog, license, canceled, the serial
  comma. A checkbox is selected or deselected, never ticked. A place of macOS is spelled as macOS spells it, and a
  path through menus reads `System Settings > General`.
- **No em or en dashes**, anywhere, and no spaced hyphen standing in for one: a colon, a comma, or parentheses say
  the same thing, and a range reads "3 to 4". Interface text writes the curly apostrophe (’), as macOS does.
- **Every translation lives in `Localization/`**, and nowhere else. Peel speaks English and 17 other languages:
  Romanian, German, French, Spanish, Portuguese (Brazilian), Italian, Japanese, Simplified and Traditional
  Chinese, Dutch, Korean, Russian, Polish, Turkish, Swedish, Czech, and Ukrainian.
- Write new or changed interface text in English, then run `python3 Scripts/sync_localizations.py` after a Debug
  build so the catalogs list it. The English is the key, so changed text loses its translations and new text has
  none: `StringCatalogTests` fails for that text, and only for it, until all 17 are written, which happens before
  the change is merged.
- A translation uses the words macOS itself uses in that language for every place, menu, and command, and writes the
  marks macOS writes there: Dutch keeps the straight apostrophe, German puts a no-break space before an ellipsis,
  and Romanian joins a Romanian word with a non-breaking hyphen (U+2011) but never a name or an option someone may
  copy. `StringCatalogTests` checks these.
- The `peel` command stays in English, since scripts read it. PeelCore returns English and never looks up a
  translation, since the package has no catalog of its own: the app words what PeelCore sends.

## Documents

- A change that alters what Peel does updates every document that describes it in the same change: README.md,
  GUIDE.md, SAFETY.md, PRIVACY.md, ARCHITECTURE.md, CHANGELOG.md, and TERMINAL.md.
- The documents say what Peel does and why, with Apple's or the tool's own documentation as the source. They don't
  name other cleaners or uninstallers, or compare Peel with them.
- `docs/` is Peel's website. Only its text changes, and only to stay true to the app; its questions are written
  twice in `index.html`, the page and its data, and a change updates `dateModified` there and `lastmod` in
  `sitemap.xml`.

## Commits and pull requests

- One change per commit, each building and passing the tests, with a message that says in plain words what changed
  for the person using Peel and why. Sign off every commit (`git commit -s`).
- One change per pull request. Its description says what goes wrong without it, how it was tested (the test that
  failed before and passes after, and the page or command it was checked on), and what couldn't be checked.
- If an assistant helped, say so in the description, and exactly how: what it wrote, what it reviewed, what it
  translated, and what you checked yourself. If none did, there is nothing to say.
