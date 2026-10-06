# How Peel is built

This page is for anyone who wants to read or change Peel's code. It describes the parts, how a removal travels
through them, and the few ideas that hold the whole thing together. [CONTRIBUTING.md](CONTRIBUTING.md) has the
rules a change has to keep, and [SAFETY.md](SAFETY.md) the full list of what Peel protects.

## The parts

Peel is four programs built from one Xcode project, and a Swift package that holds almost all of the logic.

| Part | Folder | Runs as | What it does |
|---|---|---|---|
| Peel.app | `Peel/` | You | The SwiftUI app: every page, and a model for each. |
| The helper | `PeelHelper/` | root | A launch daemon for the few things only an administrator can do: move items to the Trash and back, and start or stop another vendor's launch daemon. |
| The Finder extension | `PeelFinder/` | You, sandboxed | Adds Uninstall with Peel to Finder's menu for an app, and opens Peel with `peel://open?path=`. |
| The `peel` tool | `PeelCLI/` | You | The command line tool, shipped inside `Peel.app/Contents/Helpers`. |

```mermaid
flowchart LR
    Finder["Finder extension<br>sandboxed"] -- "peel://open" --> App["Peel.app<br>runs as you"]
    Finder --> Link["PeelLink<br>what a link says"]
    App --> Link
    CLI["peel command<br>runs as you"] --> Core["PeelCore<br>scans, matches, moves"]
    App --> Core
    App -- "XPC, administrators only" --> Helper["Helper<br>runs as root"]
    Core --> Privileged["PeelPrivileged<br>what may be touched"]
    Helper --> Privileged
```

The package, `Packages/PeelCore`, has four libraries:

- **PeelCore** decides and acts: it finds apps and their leftovers, measures folders, matches files to apps,
  and moves things to the Trash. It has no pages or windows, only three AppKit pieces the app's lists and
  sheets use (`RowCheckboxButton`, `SheetInFront`, `TextEditing`), and it speaks plain English; the app
  words everything a person reads.
- **PeelPrivileged** is the part the helper shares: which paths may be touched, what is protected, how a tool
  is run, and how a path is split into names. The helper links nothing else, so it stays small.
- **PeelCommandLine** holds the `peel` commands. `PeelCLI` is only their entry point.
- **PeelLink** says what a `peel://open?path=` link means, for the Finder extension that sends it, the
  notifications that send it too, and the app that reads it. The extension links nothing else.

Keeping the logic in the package is what makes it testable: `swift test --package-path Packages/PeelCore` runs
more than 1,700 tests without building the app.

## Where to start reading

- `Peel/PeelApp.swift`: the app's entry point, its windows, its menu commands, and the menu bar panel.
- `Peel/Views/ContentView.swift`: the main window, its sidebar, and how a page is chosen.
- `Packages/PeelCore/Sources/PeelCore/Removal/Uninstallation.swift`: what an uninstall offers, and what it selects
  for you.
- `Packages/PeelCore/Sources/PeelCore/Leftovers/LeftoverScanner.swift` and `LeftoverMatcher.swift`: where leftovers
  are looked for, and how each one is judged.
- `Packages/PeelCore/Sources/PeelCore/Removal/TrashService.swift` and `RemovalGuard.swift`: how an item moves to the
  Trash, and what is refused.
- `Packages/PeelCore/Sources/PeelPrivileged/ProtectedData.swift` and `PrivilegedPathPolicy.swift`: what nothing may
  remove, and what the helper may touch.
- `PeelHelper/HelperService.swift`: the helper's operations.
- `Packages/PeelCore/Sources/PeelCommandLine/PeelCommand.swift`, which registers the `peel` commands kept in
  `Commands/`, and `Support/Cleanup.swift`, the path the commands that remove what a scan found take.

## How a removal travels

Take the most common case, uninstalling an app. Every other page follows the same path with its own scanner.

1. **Scan.** `Uninstallation.prepare` asks `LeftoverScanner` to look through every place an app keeps files
   (`SearchLocation`): Application Support, Caches, Containers, Preferences, launch agents, plug-in folders, the
   top of the home folder, and more. A page's scan runs through its `ScanRun`, so a newer scan or the Stop
   button ends an older one, and it counts what it reads so the page can show progress.
2. **Match.** For each file, `LeftoverMatcher` weighs the evidence that it belongs to the app: its bundle
   identifier, the identifiers of what the app embeds, its application groups, its signing team, its name. A
   plug-in and a container named by a UUID are also weighed by the identifier they declare: a plug-in's name
   says what it does and a UUID says nothing, so the identifier decides whose they are. The answer is a
   `LeftoverMatch`: a confidence (`certain`, `likely`, or `possible`), the reason, the other installed apps that
   claim the file too (with the apps of the same maker that macOS knows outside the Applications folders), the
   other copies of the app that use it (any macOS knows, wherever they are, named by their place), and, when Peel
   holds it back, why (`HoldBack`).
3. **Measure.** `FileSize` walks each folder on a thread of its own, with a time budget. A size is what moving
   the item would free: a file that shares its blocks with an APFS clone counts only what it holds alone, and one
   with another name outside the folder counts nothing. A folder that doesn't answer in time, or that macOS won't
   open, even a folder inside it, has an unknown size, never zero, and every list shows it that way.
4. **Plan.** The page shows every match with its reason. Only `certain` and `likely` matches that nothing else
   claims are selected for the user (`Uninstallation.suggestedSelection`), and nothing is selected for an app
   that would stay. The user can change the selection freely, and what they choose stays through the page's
   later scans and as the helper comes and goes: `KeptSelection` keeps the checkbox of every row they could
   already choose and gives Peel's suggestion only to a row they could not, and every page that selects for the
   user and scans again on its own keeps its choices by it. Among several apps, one whose bundle the user
   deselects stays, and its files leave the selection with it (`UninstallSelection`).
5. **Move.** The question before the move freezes what it asks about, and the move takes exactly that
   (`RemovalQuestion`, which also runs one removal at a time and holds the page's scans until it is over).
   `TrashService` asks `RemovalGuard` about each item first, holds the folder around the item open, asks again
   about what the kernel calls that folder, and moves the item through it, so the thing judged is the thing
   moved. Items only an administrator can move go through the helper.
6. **Finish.** Only for what really moved: the launch jobs whose files went are stopped, and macOS is told to
   forget the preference domains whose files went.
7. **Record.** Every removal goes into History (`removals.json`, through `RemovalLog`), with where each item came
   from and where it went, so it can be put back; History keeps the most recent 20,000 items. A removal is one entry,
   even when it moved what was selected on several pages. As it records, History adds what moved to the totals Home
   shows (`totals.json`, through `RemovalTotals`), so the app and `peel` count alike. Each item is also written down
   the moment it moves (`removals.journal`, through `RemovalJournal`), so what a removal cut short moved reaches
   History the next time it is read, as an interrupted removal, and quitting the app waits for a removal until
   History has it (`QuitGuard`). While History cannot be read nothing moves (`RemovalLog.canBeRead`, asked by
   `TrashService` before a removal) until the History page starts it over. What Peel refused to move is recorded too
   (`refusals.json`), and History lists it under Not Moved, one removal to an entry.
8. **Put back.** History's Put Back reads its record as a request, not as a fact: an item returns only from a
   real Trash, only to a place the guard allows, only when it is the item that went (`TrashedItem.identity`,
   its inode and birth time, read in the Trash as it landed and asked again of the item Put Back holds open),
   and, through the helper, only if the helper's own ledger says it moved that very item from that very place.

## What keeps data safe

A handful of ideas carry most of the weight. Each is enforced in one place and tested there.

- **The Trash, never deletion.** Nothing in Peel deletes anything of the user's; what it deletes outright is its own:
  its list of refusals, when `peel history --refused --clear` is asked to forget it; the empty placeholder `TrashMover`
  makes to hold a name on a disk that cannot rename without replacing (exFAT), when the move it was made for fails; and
  the folder `PreferenceBackup` makes for a reset's saved settings, when saving fails while it is still empty. Four
  actions can't be undone by History, and each says so where it is confirmed: Homebrew's own uninstall and clean up,
  resetting an app's privacy permissions, and Force Quit for an app that is still open 10 seconds after Peel asked it to
  quit (`QuitBeforeRemoving`). Forgetting a preference domain happens only once its file is in the Trash, so putting the
  file back undoes it, or, when saved settings are put back, once the settings in use are saved as a copy of their own
  (`PreferenceBackup`). Every `brew` call runs without Homebrew's automatic cleanup (`HOMEBREW_NO_INSTALL_CLEANUP`), so
  an upgrade never deletes on its own; when a `brew.env` file of the user's turns that back on (`Homebrew.overrides()`,
  from `brew config`), the Homebrew page says so and leaves upgrades to Terminal.
- **One guard.** `RemovalGuard` decides, for the app and the `peel` tool alike, whether an item may move. Its
  list of what nothing can bring back lives in `ProtectedData`, in PeelPrivileged, so the helper applies the
  same list without asking the app. The guard judges the item and not the spelling of its path: each rule is
  asked of the path as written, as found on disk, and as the kernel names the item, and the places it protects
  by path (in the home, the keychains, and the folders that stay themselves) are known by device and inode as
  well, wherever a link leads them. It finds those places without opening them, since opening a folder inside
  another app's container makes macOS ask for that app's data. A path is read name by name (`PathComponents`),
  never as text, since a slash and a combining mark after it are one Swift `Character`.
- **Exclusions everywhere.** The user's exclusions reach every scanner, so an excluded item never appears, and
  a folder with something excluded inside is never moved.
- **Unknown stays unknown.** A size that couldn't be measured, a list a tool didn't give, an answer that didn't
  come, whether an item is still in the Trash when macOS won't let Peel look (`TrashedItem.standing`): each is
  kept as not known, shown as such, never selected for the user, and never forgotten from History.
- **Every hold back has a reason.** When Peel takes a checkmark away, the row says why.

## The helper

The helper (`com.tuguidragos.Peel.Helper`) is registered with `SMAppService` when the user asks for it, and
macOS asks the user to approve it once. It talks to the app over XPC.

- It answers administrators only, asked when a connection opens and again with each message, and it accepts
  only a copy of Peel signed by the same team, checked when a connection opens and for every message after it.
  A released helper refuses a build that can be debugged, and launchd starts the helper only as the team's own
  build of it (`SpawnConstraint` in its launchd property list).
- It does three things: moves items to the Trash, puts them back, and starts, stops, enables, or disables another
  vendor's launch daemon, never one macOS ships and never itself. When Peel is removed, it also moves its own ledger
  to the Trash.
- It serves a fixed list of folders (`PrivilegedPathPolicy`), refuses everything else, and refuses whatever
  `ProtectedData` protects. It has no shell.
- It opens folders by descriptor and works through them, so a path swapped for a link after the check leads
  nowhere.
- It keeps a ledger of what it moved, in a folder only root can write (`/private/var/db/com.tuguidragos.Peel.Helper`),
  and puts back only what that ledger knows. While the ledger can't be read it moves nothing, and one it can't make
  sense of is kept under another name (`DamagedFile`), never written over.
- Any change to the helper means bumping `HelperIdentity.protocolVersion`, which asks users to install the
  helper again.

## The app

- **Pages and models.** The sidebar lists the tools. Each has its page in `Peel/Views/<Tool>/`, but for
  Applications, whose views sit directly in `Peel/Views/`, and a model in `Peel/Model/` (`AppLibrary`,
  `OrphanLibrary`, `DuplicateLibrary`, and so on) that owns its scan and its selection. The pages share
  `RemovalRow` for a row that can be selected and `RemovalBar` for the button that moves the selection. On the
  pages that free space (Orphaned Files, Space, Developer, Build Artifacts, Installers and Backups, Duplicates,
  and File Search) the selection travels: what is selected on every such page the user has opened stays selected,
  and Move to Trash on any of them moves it all as one removal, each page's part by its own tool with that tool's
  checks (`SelectionCarrier`, over `CarriedSelection` in PeelCore).
- **Concurrency.** The app target runs on the main actor by default. Heavy work lives in PeelCore and is marked
  `@concurrent`, so it runs off the main actor.
- **Two looks.** Home, the menu bar panel, and About use Peel's own look, a paper sheet with stickers. Every
  other page reads as macOS: system type, forms, native controls, and Liquid Glass only on floating controls.
- **Languages.** Every string a person reads is in the string catalogs in `Localization/`, translated into 17
  languages. The key is the English, so changing a sentence means translating it again; the tests fail until
  every language has it. PeelCore never translates: it returns plain English, and the app turns known
  sentences into the reader's language (`FixedSentence`).
- **Terminal.** The Terminal page writes Terminal's own preferences: Peel's themes as profiles of their own, each
  built by `TerminalProfile` from Apple's Clear Dark, the profile Terminal opens with, and two keys in the Peel theme
  in use (`TerminalOption`). `TerminalThemeLedger` keeps what Terminal used before and the fingerprint of each profile
  Peel wrote, so Put Back takes away only a profile still as Peel wrote it. Peel writes only while Terminal is
  closed: an open Terminal does not read a change made outside it, and writes its own settings over it. The Shell
  and SSH tabs write only files of Peel's own in its folder, `Terminal/zshrc` (`ShellFile`, with the prompt from
  `Prompt`) and `Terminal/ssh_config` (`SSHFile`), which zsh and ssh read through lines the person adds: Peel
  never edits `~/.zshrc` or `~/.ssh/config`. The Git tab changes Git's settings only through `git config --global`
  (`GitConfig`), and `GitLedger` keeps what each key held, so turning a setting off puts it back. A setting is
  offered only when the tool on the Mac knows it: zsh lists its options and functions (`ZshRequirements`), Git its
  keys (`git help --config`), and ssh accepts the options on its own command line. The Tools tab installs nothing:
  `TerminalTool` gives each tool's Homebrew formulae and the lines its documentation gives, and Homebrew is asked
  whether it still offers them.
- **Watching the Trash.** `TrashMonitor` notices an app the user moves to the Trash: the home's, and the Trash of
  each other disk Peel lists apps on (`VolumeTrashes`), where an app thrown away from that disk lands. `TrashService`
  tells it about Peel's own moves (`OwnTrashMoves`), by where each item landed, so Peel never offers to clean up
  after itself.

## The `peel` tool

`PeelCommandLine` builds each command on `swift-argument-parser`. The commands that remove what a scan found
(`peel orphans`, `caches`, `projects`, and `duplicates`) go through `Cleanup`, and `peel uninstall`, which also
takes out the app's Dock icon and may reset its permissions, has a plan and a question of its own and ends through
`Cleanup.end`. So all of them ask, record, and exit the same way: they print the plan with the guard's answer beside
each item, stop there with `--dry-run`, ask unless given `-y`, exit 2 when the answer is no and 1 when a removal
couldn't finish, and write the same History the app shows. The tool never uses the helper. Everything it prints goes
through `Output`, so scripts can read it: its own words are plain ASCII, and names, paths, and what macOS says in an
error are printed as they are, in UTF-8, with every character that could hide or reorder text shown as `?`
(`PlainText`). A long scan says how far it has got on one line of standard error, written over itself and cleared
before anything else is printed (`ProgressLine`). Only a terminal shows it, and only while `peel` is its foreground
job, so a script reading standard error gets nothing.

The app's build puts the tool's shell completions, written by the tool it just built, and its manual page,
`Support/peel.1`, in `Peel.app/Contents/Resources/completions` and `man` (the Command Line Documentation phase),
where a Homebrew install takes them from.

## What Peel writes on disk

| Where | What |
|---|---|
| `~/Library/Application Support/Peel/removals.json` | History: every removal, so it can be put back. |
| `~/Library/Application Support/Peel/removals.journal` | What a removal has moved so far, item by item, until History has it. |
| `~/Library/Application Support/Peel/refusals.json` | What Peel was asked to move and refused, and why. |
| `~/Library/Application Support/Peel/totals.json` | The totals Home and the menu bar panel show: what the app and `peel` moved since Peel was installed. |
| `~/Library/Application Support/Peel/exclusions.json` | The user's exclusions. |
| `~/Library/Application Support/Peel/Preference Backups/` | The settings Peel saved before resetting an app. |
| `~/Library/Application Support/Peel/digests.bin` | What Duplicates already read, so an unchanged file isn't read again. |
| `~/Library/Application Support/Peel/apps.json`, `teams.json` | What Peel remembers about apps and their signing teams between launches. |
| `~/Library/Application Support/Peel/orphan-owners.json` | The orphaned files the user said belong to an installed app. |
| `~/Library/Application Support/Peel/dock-tiles.json` | The Dock icons an uninstall took out, and where each was, so History puts them back with their app. |
| `~/Library/Application Support/Peel/app-folders.json` | The folders the user chose for Peel to look for apps in, beside the Applications folders. |
| `~/Library/Application Support/Peel/homebrew.json` | The `brew` the user chose for a Homebrew in a folder of its own, which the app and `peel` run. |
| `~/Library/Application Support/Peel/Terminal/zshrc`, `Terminal/ssh_config` | The shell and ssh settings chosen on the Terminal page, which zsh and ssh read through the lines the user adds. |
| `~/Library/Application Support/Peel/release-notes.json` | What is new in each update that waits, as the app's own sources say it, so its page shows it with no connection. |
| `/private/var/db/com.tuguidragos.Peel.Helper/` | The helper's ledger of what it moved. |
| Peel's preferences | Settings, the day Peel was installed, what each tool found the last time it looked, the last answer of each update check, and what the tweaks, Terminal, and Git held before Peel changed them, so turning a setting off puts that back. |

Remove Peel, in Settings, takes all of it to the Trash. The helper moves its own ledger there, since nothing else
can, just before Peel unregisters it. It is the only way Peel removes itself: Peel's own page in Applications,
and Peel among several chosen apps, list it and select nothing of it (`Uninstallation.isPeel`), and
`peel uninstall` refuses it. For a copy Homebrew installed, Settings shows `brew uninstall --zap` in its place
(`SettingsView`).

## Testing

- `swift test --package-path Packages/PeelCore` runs the whole suite. Tests use temporary folders
  (`TemporaryDirectory`) and never touch the user's own state.
- Scanners take their slow parts as parameters (how to measure a folder, how to run a tool), so a test can
  stand in for a folder that never answers or a tool that fails.
- The `Attack*Tests` files try to get past the safety rules on purpose: another case, a link, a `/.vol` path, a
  folder swapped between the check and the move.
- A few tests read this Mac instead of a fixture, and the slowest ones run only when asked for
  (`PEEL_TEST_THIS_MAC=1`).
- `PeelUITests` runs Xcode's accessibility audit on every page, About, Settings, and the menu bar panel, in both
  appearances. It drives the pointer and quits a Peel that is open, so it has a scheme of its own and runs by hand
  before a release; the checks only build it.
- `Scripts/sync_localizations.py --check` fails when a string catalog is behind the code, and
  `Scripts/generate_manual.py --check` when the manual page of `peel` is behind the tool.

## Releases

`Scripts/release.sh` builds a Release copy, signs it with a Developer ID, has Apple notarize it, staples the ticket,
checks the result with Gatekeeper, and prints the path and SHA-256 of `Peel-<version>.dmg`, for people, and of
`Peel-<version>.zip`, for Homebrew. The disk image is signed, notarized, and stapled too. It opens on a window of
the album's paper with an arc from Peel to Applications, which `Scripts/make_dmg.sh` lays out with dmgbuild, run by
uv, so nothing drives Finder; the background carries no words, since Finder writes the names in each Mac's language.
It starts only from a committed tree whose package tests pass with warnings as errors, and it refuses a build in
which any of the four programs can be debugged or lacks the arm64e slice, in which a language is missing, or which
`syspolicy_check distribution` says macOS would not open.

A Release build of every program has pointer authentication (`ENABLE_POINTER_AUTHENTICATION`, an arm64e slice
beside arm64 and x86_64), and the helper the rest of Enhanced Security too. Xcode gives the Swift packages only the
settings of the command line, so a Release build passes that setting there as well, with
`MACOSX_DEPLOYMENT_TARGET=26.0`: a package that names no platform, such as swift-argument-parser, would otherwise
be built for an older macOS with its class data unsigned, and the linker would then leave the class data of the
whole `peel` tool unsigned. `release.sh` and the Checks workflow pass both, and Xcode's own Archive, which cannot,
fails. A Debug build leaves pointer authentication off, since it builds only the Mac's own architecture, which the
programs would read as arm64e and the packages as arm64.
