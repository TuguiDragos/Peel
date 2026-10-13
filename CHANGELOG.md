# Changelog

Every release of Peel is listed here, newest first. The version is the one About Peel shows, and each entry groups
its changes the way [Keep a Changelog](https://keepachangelog.com/) suggests.

## 1.1.0 (2026-10-13)

> [!IMPORTANT]
> Peel 1.0.1 can't install an update itself. To update from it, quit Peel, move it from Applications to the Trash,
> and drag the new Peel into Applications: your History, exclusions, and settings stay. If Homebrew installed it, run
> `brew upgrade --cask peel` instead. If Home then says the helper isn't answering, choose Repair. From 1.1.0 on,
> Peel updates itself when you choose Install Update.

Peel now updates itself, sets apart what only an administrator can remove, and protects more of what nothing could
bring back, from files that sync to your other devices to chats and game saves. It finds more to clean, shows how far
a removal has got, and says within seconds when its helper isn't answering.

### Added

- **Updates:** Peel updates itself, through Sparkle. Choose Check for Updates… in the Peel menu, or Install Update…
  in About Peel when it says a new version is out; while Check for app updates is on, Peel also looks once a day. It
  shows what is new and installs the update only when you choose, once it has checked that it is signed as Peel's.
- **Tweaks:** On macOS 27, Privacy has an Apple Intelligence section whose rows open the place where macOS keeps each
  feature's switch, as Apple's guide names it. Peel changes none of them.
- **Removals:** Says when an audio driver Peel moved stays loaded until you restart your Mac.
- **History:** On macOS 27, says under an audio driver in the Trash that it loads only after a restart once put
  back, and under an app that it shared its storage with another copy.
- **Applications:** Lists and uninstalls apps whose Info.plist names no identifier, such as OpenShot Video Editor.
- **Applications:** Move to Trash shows which app it is waiting for to quit and how many items have moved, on an
  app's page and on several apps' page.
- **Applications:** On several apps' page, the two options sit side by side above the lists, and a button jumps to
  each list.
- **Applications:** On macOS 27, says after an uninstall when macOS will still start the app's login items from the
  Trash, with a button that opens Login Items & Extensions, and `peel uninstall` says it too.
- **Orphaned Files:** Needs an Administrator, a new section at the head of the list, gathers what only an
  administrator can remove, says why Peel leaves it and how to remove it in Finder, and offers Show in Finder.
- **Orphaned Files:** Remembers what an uninstall left for an administrator, so it shows there once the app is gone,
  and the removal's alert says how many items stayed, with Open Orphaned Files.
- **Orphaned Files:** Lists the folders a gone code editor or JetBrains IDE named in its product file, and the
  manifests browsers keep for a helper program that is gone, which Peel's helper can now move from `/Library` too.
- **Orphaned Files:** Says that only macOS removes its copy of a system extension, and the steps that make it do so,
  names the app it was installed for once that app is gone, and on macOS 27 says at the head of a group why nothing
  in it can move.
- **Space:** A new area, Homebrew Service Logs, offers the logs Homebrew's services write in `/opt/homebrew/var/log`,
  never their folders, and doesn't recommend a log written in the last 15 minutes.
- **Space:** Says at the top of a page how much of the folder moves there, which developer tools' folders hold the
  rest, and opens Developer for them.
- **Space:** On macOS 27, says how much Apple Intelligence may keep on this Mac, by Apple's own figures, and how much
  the AI models and datasets on the Developer page take.
- **Developer:** Lists the models more AI apps and libraries download, never selected for you: AnythingLLM,
  InvokeAI, ComfyUI, Mochi Diffusion, oMLX, GPT4All's app, TensorFlow Hub, Chroma, and twenty libraries and tools
  such as CLIP, EasyOCR, rembg, Docling, MLC LLM, and Vosk.
- **Developer:** Lists more caches: Google's updater's downloads, the Clojure CLI's classpaths, Metro's and Node's
  caches in the temporary folder, Gradle's native libraries, sbt's preloaded artifacts, Cabal's older folder, old
  Electron downloads, rustup's temporary files, Java Web Start's cache, Xcode's documentation index, and Chromium's
  former WebGPU cache.
- **Developer:** Lists VS Code's own caches and logs for VS Code Insiders, Windsurf, Devin, and every other editor
  built on VS Code, the caches of every build of Brave and of Brave Origin, and those of the sessions an Electron app
  opens, never unsaved files or profile data.
- **Developer:** Lists the caches and logs of coding agents such as Codex CLI, Kilo Code, Continue, and Cline, never
  their sessions, settings, or keys, and what MobileBuildMCP builds for each workspace.
- **Developer:** Offers the Git clone of CocoaPods' public specs, but only when it comes from CocoaPods' own
  repository.
- **Build Artifacts:** Knows 45 more tools: aider, atspkg, Autoconf, AWS SAM, Bloop, Bower, the Clojure CLI,
  Docusaurus, Eleventy, Eleventy Fetch, Elm, Hakyll, Jekyll, Lexical, LiquidHaskell, Meson, Mill, Next LS, Nx, nyc,
  Pants, PDM, Pixi, psc-package, Pulp, PureScript, Pyre, pytype, Quarto, React Router, reco, Remix, two TypeScript
  plugins for Rollup, Ruby Sass, sbt, the Serverless Framework, the Shopify CLI, SolidStart, Spago, SWC, Trigger.dev,
  Vercel, Vite SSG, and xwin. It also knows the platform folders Flutter generates.
- **Build Artifacts:** Names every chosen folder it couldn't search, and why, in the app and in `peel projects`,
  instead of saying that nothing was built there.
- **Installers and Backups:** Finds the downloads Safari never finished, and the updates apps downloaded through
  electron-updater, held back while their app runs.
- **iCloud Drive:** Shows downloads in the folders Finder shows them in, named as Finder names them, the biggest
  first, with a checkbox for each folder.
- **iCloud Drive:** Says how many downloads it leaves out because another copy on this Mac shares their space, and on
  macOS 27 counts the files Remove Downloads frees and lets you stop it.
- **Background Items:** On macOS 27, offers Remove for a job a deleted app left loaded, and says when an item runs
  from the Trash.
- **Command line:** `peel orphans` lists apart what needs an administrator, as `forAnAdministrator` in its JSON, and
  says when a match is only a hint; `peel uninstall` says how many items stayed for an administrator; and
  `peel apps --json` writes `null` for an app with no identifier.

### Changed

- **Safety:** Never moves anything that syncs to your other devices, through iCloud or an app such as Syncthing,
  Resilio Sync, Synology Drive, or MEGA, nor the records iCloud keeps to stay in sync, from any page or from `peel`.
- **Safety:** Never selects for you what may exist only on this Mac, such as WhatsApp's chats, Steam's game saves,
  Postgres.app's data folders, OBS's scene collections, and the backups an app keeps. They're listed with the reason,
  and you can still select them.
- **Safety:** Never offers to move a Godot project's export credentials, another installed app's folders, what one of
  Apple's packages installed, or the folder crash reports are saved in: Space now offers only the reports.
- **Safety:** Never selects for you a launch job that runs another installed app's program, Chrome's native messaging
  folders while Brave reads them, or a folder holding a Solana program's key.
- **Safety:** Never looks into a folder that lives only in the cloud, since listing it would download it.
- **Safety:** The helper's record of what it moves reaches the disk before it moves anything, and History right
  after a removal, so a power cut can't lose the way back.
- **Helper:** Says within seconds, even while Peel is busy, when the helper isn't answering, instead of after two
  minutes, and Home offers Repair. Home and Settings say Installing…, Repairing…, or Uninstalling… while it changes,
  and Home's other rows no longer wait for it.
- **Applications:** Leaves an app with a system extension, such as a VPN or a virtual camera, to Finder, since only
  Finder's move tells macOS to remove the extension: its page, Package Receipts, the Homebrew page, and
  `peel uninstall` say so. On macOS 27, Peel also says how System Settings deletes a network extension.
- **Applications:** Leaves security and management agents to their makers' uninstallers, with the documented step
  and a link: GlobalProtect, Cortex XDR, Cisco Secure Client, ESET Endpoint Security, Microsoft Defender, Netskope
  Client, and FortiClient. TeamViewer's system parts and the authorization plug-ins macOS loads at login are left to
  their own uninstallers too, and an uninstaller app a maker documents, such as Chrome Remote Desktop Host
  Uninstaller, is offered to open rather than moved.
- **Applications:** Uninstalls Citrix Workspace the way Citrix documents, by moving the app, and says first that
  Citrix's uninstaller will then delete the app and its system files, which History can't bring back.
- **Applications:** When an app's own background programs are all that keep it from moving, as with Teams and
  OneDrive, Peel stops them, moves the app, and starts them again if it stays.
- **Applications:** Says who holds an item that stays and what to do: quit the app, stop a program that has no window
  in Background Items, or, when macOS itself is using the item, let it stay.
- **Applications:** Takes along more of what is the app's: the folder its updater downloads into, the folders a
  JetBrains IDE or a VS Code editor names in its product file, an emptied folder named for the developer its
  signature names, Homebrew's record of a cask installed from a package, and the receipt of a package that wrote only
  the app.
- **Applications:** Lists Xcode's simulators when you uninstall Xcode, for you to review.
- **Space:** Holds back a cache something wrote to in the last 15 minutes, and keeps an update an open app downloaded
  until the app quits.
- **Developer:** Lists Dart's package store as installed packages, never selected, since every Dart and Flutter
  project builds from it.
- **Build Artifacts:** Holds back a build folder Git tracks, reading the repository's own index: Peel never runs Git
  in your project.
- **Build Artifacts:** Groups what a build leaves deep in a project, such as Python's `__pycache__` folders, under
  that project, so a repository reads as one project rather than one per package.
- **Build Artifacts:** Lists Meson's build folders under Meson whatever their name, and never selects them, since they
  keep the options they were set up with.
- **Build Artifacts:** Refuses to search a folder where apps and tools keep what they install, such as an editor's
  extensions.
- **Package Receipts:** Leaves for you to choose a folder a package made that something else has filled.
- **Duplicates:** Copies with different Finder comments are no longer duplicates.
- **iCloud Drive:** Lists only what Finder shows, the Documents of each app's folder, never the data an app keeps
  beside them.

### Fixed

- **Tweaks:** The screenshot folder can no longer be the Trash, and a folder screenshots can't be saved in says why.
- **Terminal:** The Git tab leaves a setting to a file your settings include, so Peel's value never wins over yours,
  and the switch that reuses ssh connections says to leave it off with two accounts on one server.
- **History:** Put Back brings an item back under the name the disk gives it, registers an app it brings back with
  macOS, judges with your exclusions as `peel restore` does, and stays off, with Undo, while History or the
  exclusions can't be read.
- **History:** If Peel 1.0.1 moved your crash reports folder, History can now put it back.
- **Settings:** The copies of settings a reset saves are now listed, and putting one back leaves an excluded app
  alone.
- **Settings:** App Folders refuses the Trash, so apps there no longer count as installed.
- **Watch the Trash:** No longer offers an app's leftovers when another copy of the app is still installed.
- **Applications:** An uninstall no longer selects a folder of macOS or of another tool that only bears the app's
  name, nor the receipts of a related app that stays installed.
- **Applications:** An app Peel saw go keeps its files: they're never selected with another app whose identifier
  begins the same, and Orphaned Files lists them even while another app of the same maker is installed.
- **Applications:** Uninstalling Chrome no longer takes Chrome Remote Desktop's browser manifests, nor does Orphaned
  Files while its host is installed, and the manifests in the folders of Chrome's other channels are found.
- **Applications:** Totals no longer count twice an item that sits inside another one being moved.
- **Applications:** Storage that Sparkle's updater services share among apps is never taken as one app's at its
  uninstall.
- **Applications:** Peel never moves a folder it runs from, and no longer asks to quit a program of another account,
  which it could never quit.
- **Applications:** On several apps' page, an app's bundle stays among the apps when another chosen app lists it, and
  a click on an option no longer holds the window.
- **Applications:** The options to reset privacy permissions and remove from the Dock show only for an app that can
  move.
- **Applications:** An emptied maker's folder in the Mac's Library goes with the app when its files went through the
  helper.
- **Applications:** An item already gone when its turn came is no longer reported as a failure, and a program that
  holds an item is named in full.
- **Applications:** An app you exclude is never moved, even when you exclude it while its question is open, and never
  put back.
- **Applications:** Reading an app no longer registers it with macOS, so a copy on another disk or in a folder of old
  versions isn't made known to macOS.
- **Reset:** Starts nothing while History or the exclusions can't be read, and offers nothing for an app in the Trash
  or one you exclude, from the moment its page opens.
- **Reset:** Promises a copy of the settings only when it makes one, offers the copy back only once the settings were
  cleared, stays open while they go back, and closes its question when what it asks about changes.
- **Reset:** History names a reset and a saved copy of settings as what they are, and the Edit menu says Undo Reset.
- **Orphaned Files:** A file is listed once however many places reach it, and the settings a running background job
  keeps beside its file are no longer listed.
- **Package Receipts and Homebrew:** Forget Receipt, Forget Cask, and Forget All turn off while History or the
  exclusions can't be read, as every other removal does.
- **Homebrew:** A cask whose packages are all gone joins the casks already gone and can be forgotten, and an excluded
  app also stops `brew uninstall` of a cask installed from a package.
- **Space:** The command that deletes outdated simulator runtimes shows only where the simulator tool knows it.
- **Developer:** An app whose name holds a bracket or a star no longer has another folder's caches listed as its own.
- **Build Artifacts:** A folder holding only build output no longer reads as too large to date.
- **Build Artifacts:** A project's Time Machine switch turns off again, and keeps in backups the folders Peel holds
  back, such as one with a wallet, a key, or a repository inside.
- **Selections across pages:** An item selected on two pages counts and moves once, instead of counting twice and
  failing on the second page.
- **Duplicates:** A disk's own Trash is never scanned, and the files of a chosen folder offered whole aren't offered
  again.
- **iCloud Drive:** Names each app's folder as macOS shows it.
- **Scans:** iCloud Drive, Build Artifacts, and Intel Software no longer skip the folder that comes right after
  certain files, which hid downloads, recent edits, and Intel programs.
- **File Search:** No longer lists what syncs to your other devices.
- **Background Items:** No longer calls an app's login item or agent orphaned because launchctl names no program for
  it.
- **Remove Peel:** Ends Peel's Finder extension, which no longer offers Uninstall with Peel… once Peel is gone, takes
  no step while Peel itself can't move, no longer waits minutes for a helper that can't start, and says what stayed
  in your language.
- **Command line:** `peel restore` lists only what can go back and says why each other item stays, and
  `peel inventory` and `peel updates` know the apps a cask installed from a package.

### Security

- Only an administrator can install, repair, or uninstall Peel's helper. Before, a standard account could uninstall
  it for every administrator of the Mac.
- A launch job's file can no longer mislead Peel through a program path that hides a NUL character.

## 1.0.1 (2026-10-08)

The first public release, for macOS 26 and later, on every Mac that runs it: Apple silicon, and the Intel Macs
macOS 26 supports.

### Added

- Uninstalls apps, web apps Safari made and iPhone and iPad apps among them, together with the files they
  leave behind, and shows for each file why it matched and how sure Peel is.
- Takes an app's icon out of the Dock with the app, and resets the privacy permissions macOS gave it when you ask.
- Shows what each app opens by default, and what would open those files and links once it's gone.
- Finds files left by apps that are gone, caches of developer tools, what builds left in your projects,
  duplicate files and folders, installers and backups, files already safe in iCloud, large and old files, and
  what is taking up space.
- Leaves a project's build folders out of Time Machine when you ask it to.
- Resets an app's settings without uninstalling it, after saving them so they can be put back.
- Lists background items, extensions, plug-ins, what installer packages put on your Mac, and software that still
  needs Rosetta; starts, stops, enables, disables, or moves to the Trash a background item; moves a plug-in, or
  what a package installed, to the Trash; and forgets a package's receipt.
- Runs Homebrew's update, upgrade, uninstall, clean up, repair taps, and health check, scans your formulae for
  known vulnerabilities, and forgets a cask whose app is already gone, through the Trash.
- Changes settings macOS has, many of which it doesn't show, and puts back what was there when you turn one off.
- Gives Terminal one of 29 dark themes built on Apple's Clear Dark, puts back the profile it used before, and can
  leave out the "Last login" line, keep Terminal from reopening its windows, make Option the Meta key, and silence
  the bell.
- Sets up the command line from the same page: choose a prompt, turn on settings that zsh, Git, and ssh already
  have, and copy the Homebrew commands for command-line tools worth having, with the lines each one needs.
- Moves what it removes to the Trash instead of deleting it, says first when something can't be undone, and
  keeps a History that puts it back and lists what it didn't move, with the reason.
- Refuses to remove what nothing could bring back, such as keychains, crypto wallets, Mail, and photo libraries,
  whoever asks it to.
- Moves what sits in folders only an administrator can change, and puts it back, through a helper that answers
  administrators only, once you approve it.
- Keeps what you select on the pages that free space while you look at the others, and moves it all at once, as
  one entry in History.
- Selects what Peel recommends, everything you can select, or nothing, on one list or on every page of a tool at
  once, and asks first before it selects anything Peel doesn't recommend.
- Leaves alone the files, folders, and apps you exclude, and the folders named with an excluded app's identifier.
- Starts the sidebar with the tools most people use, and keeps each tool you turn on or off in Settings.
- Opens on Home: this Mac's chip, memory, and macOS version, how much of its disk is free, what Peel has moved to
  the Trash so far, and which permissions are on.
- Checks your apps for updates, shows what is new in each update that waits, keeps quiet about a version you skip
  or an app you stop checking, and watches the Trash for apps you remove yourself.
- Finds apps outside the Applications folders, in folders you add.
- Shows in the menu bar what each tool found last, and opens at login, when you turn those on.
- Notifies you of app updates, a Homebrew upgrade that ends or fails, a disk almost full, and an app you move to
  the Trash yourself, as you choose.
- Says in About when a new version of Peel is out, with where to get it, and downloads nothing itself.
- Exports what is installed and where each app came from, as JSON, CSV, plain text, or a Brewfile.
- Comes with the `peel` command for Terminal, a Finder extension, and actions for Shortcuts.
- Removes itself from Settings, with its helper, its login item, the link to the `peel` command, and its own
  files, but for the shell and ssh settings, which go on working.
- Speaks English and 17 other languages.
