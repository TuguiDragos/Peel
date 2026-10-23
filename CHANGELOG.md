# Changelog

Every release of Peel is listed here, newest first. The version is the one About Peel shows, and each entry groups
its changes the way [Keep a Changelog](https://keepachangelog.com/) suggests.

## 1.2.0 (not released yet)

### Added

#### Terminal

- With Peel's prompt on, the Shell tab asks zsh which prompt a new window shows, and names the function that sets its
  own before each command, as Starship and Powerlevel10k do, or says that something sets it after Peel's file is read.
- The Shell, SSH, and Git tabs say when Peel's own file couldn't be read or when zsh, ssh, or Git didn't answer, and the
  Tools tab says so while it asks Homebrew.

#### Settings

- Privacy lists `api.github.com`, which Homebrew asks before an update or upgrade whether it and the taps kept on GitHub
  have changed.

#### Applications

- Bitdefender Endpoint Security for Mac and Sophos Endpoint are left to their makers' own uninstallers, and the app's
  page gives the maker's step.
- ExpressVPN, Private Internet Access, Cloudflare WARP, ZeroTier, Tunnelblick, and IVPN are left to their makers' own
  uninstallers, which also turn off what they keep in the system, such as a kill switch or a network extension: the
  app's page gives the command, opens the app whose own command removes it, or links the maker's instructions for the
  uninstaller on its disk image.
- Zscaler Client Connector and Arq are left to their makers' own uninstallers: Zscaler's asks for the uninstall password
  your organization set, and Arq's asks whether to delete its backup settings.
- Cisco AnyConnect, and Secure Client up to 5.1.2, are left to Cisco's uninstall script, the one that is on your Mac,
  and Symantec Endpoint Protection to the uninstall command in its own window.
- After a removal, Peel reads the files your shell runs when it starts and names the lines that still point to what
  moved, such as a `PATH` entry or an alias into the app, in the alert and in `peel uninstall`. It changes none of these
  files.

#### Developer

- Spring Boot, with the working folders its servers leave in the temporary folder each time they start (`tomcat.`,
  `tomcat-docbase.` or `jetty-docbase.` with the port and a number). One something wrote to in the last 15 minutes is
  listed and not selected, since a server still running may be using it.
- Lists the templates create-expo-app keeps in the temporary folder, and the Chrome that agent-browser downloads, which
  `agent-browser install` fetches again.

#### Build Artifacts

- Lists a project's `.expo` folder, and its `.astro` folder, which keeps the preferences set with `astro preferences`
  and is never selected.

### Changed

#### Tweaks

- Turn All Off puts back only what Peel changed and leaves what you set yourself as it is; the sentence under it counts
  Peel's changes, and its question names them.
- A setting set for this Mac alone, for every account by an administrator, or for every app at once shows with a lock,
  as one a profile locks does, since Peel can't change it from where it writes.
- The screenshot name is saved on Return or Save only.
- The notes say that a restart of Finder stops anything it is copying, that the window manager restarts for the gaps
  between tiled windows, and that macOS's menu bar items restart for the seconds on the clock.

#### Terminal

- Sign commits with your SSH key signs with the key Git already signs with, and its row names the key in use.
- The Tools tab asks Homebrew which tools it still offers only while Homebrew's own settings wouldn't make it update its
  lists over the network first.

#### Settings

- Privacy names the country an update check tells the App Store: that of the store an iPhone or iPad app came from, or
  else your Mac's region.

#### Applications

- Applications and `peel updates` ask the App Store about at most 20 apps a minute, the pace Apple documents for its
  lookup, so a Mac with many apps from the App Store is checked within it rather than all at once.
- Rescan asks about every app's updates again at once, whatever each one's schedule says.
- Peel reads Homebrew again once Homebrew has checked for new versions since Peel last read it, as after `brew update`
  in Terminal.
- With The App Store or The app's own feed preferred, an app its own source can't answer for gets what Homebrew knows,
  as with Automatic, and `peel updates` says the same as Applications. The note under Prefer updates from in Settings
  gives the order.
- A folder named like the app without the word of its release channel, as Zed Nightly keeps its settings in `zed`, is
  shown for review and never selected, and Orphaned Files counts it as the installed channel's.

#### Applications and Orphaned Files

- A sign-in a tool saved when you logged in, such as Docker's `config.json` or the folder of the Google Cloud CLI, is
  listed and never selected, since logging in again brings it back.
- ZeroTier's identity on its networks and Tunnelblick's shared VPN configurations, both kept in
  `/Library/Application Support`, are listed and never selected, like a VPN's connections in your home folder.
- The group folder where 1Password 7 kept its standalone vaults and their daily backups is listed and never selected,
  also when you uninstall 1Password 8, which uses it too.
- A folder holding a 1Password vault kept outside an account, `.opvault` or `.agilekeychain`, is listed and never
  selected, like one holding a KeePass database, and the pages that measure folders hold it back too.
- A torrent client's list of torrents and how far each one got, as Transmission, qBittorrent, BiglyBT, Deluge, Motrix,
  and WebTorrent keep them, is listed and never selected: without it the app forgets every transfer.
- The user profile of LibreOffice and Apache OpenOffice, with your own templates, AutoText, dictionaries, and the
  automatic backups of your documents, is listed and never selected.
- iTerm2's folder in Application Support, with the scripts and dynamic profiles you wrote, is listed and never selected.

#### Space

- A cache folder holding a `Clipboard` folder, as Raycast's holds the images of your clipboard history, is held back
  like other work an app keeps only in a cache.

### Fixed

#### Tweaks

- A number written as text, as `defaults write` stores it with no type flag, reads as the number it spells, so a wait
  before the hidden Dock slides out set that way no longer shows as off.
- Put Back on the screenshot folder leaves the setting to macOS, and says so, when the folder from before isn't there
  anymore, is in the Trash, or can't be written to, instead of writing back a folder screenshots can't be saved in. A
  folder on a disk that isn't connected is put back as it was, for when the disk is back.
- The folder for screenshots is written without a slash at its end.
- A write macOS refused keeps its word under the row until that tweak's next write lands, whatever other rows change.

#### Terminal

- Choosing a theme, changing one of its switches, or putting Terminal back writes nothing over Terminal's profiles when
  they can't be read, and the Themes tab says so.
- The command the Shell tab gives for `~/.zshrc` starts Peel's line on a line of its own, so a file whose last line has
  no newline after it keeps that line, and the tab says that zsh reads Peel's settings only for a line that reads them.
- Turning off Sign commits with your SSH key puts back every key as it was, so signing you had with another format, such
  as GPG, goes on as before.
- The Git tab writes down what each key held before Git writes the key, and quitting Peel waits for the change.
- Turn All Off on the Shell and SSH tabs never writes over a file of Peel's own that couldn't be read.
- The Terminal tab says from the start when Terminal's profiles can't be read, instead of asking you to choose a theme.
- Quitting Terminal from Peel's question applies the theme at once: Terminal counts as closed as soon as its process has
  ended, so the question no longer comes back a second time.

#### History

- Put Back makes each folder missing on the way back only after the guard allows it, through the folder it just made,
  and takes those folders back when the move is then refused.
- What the helper moved while its answer was lost is found in the Trash and recorded also without Full Disk Access.

#### Settings

- Open at Login reads and changes the login item away from the main thread, so the window no longer waits for macOS.
- Remove Peel gives you the helper's ledger as the helper moves it to the Trash, so emptying the Trash needs no
  administrator's password for it.
- When many of the folders you choose can't be used, the alert of App Folders and of Exclusions names the first few
  and counts the others, so its button stays on the screen, as do the alerts of Build Artifacts and Duplicates.

#### Applications

- When many apps stay after a removal, as without App Management, the alert names the first few and counts the others,
  so its Open System Settings button stays on the screen. It does the same with the apps to quit and the lines of your
  shell startup files, and Copy Details, offered whenever the alert names only the first few, gives them all. Several
  apps' question names the first few apps that go and that stay the same way.
- iPhone and iPad apps installed on the Mac from the App Store are checked for updates against their own listing, in the
  store they came from, and Mac apps sold together with their iPhone version against their Mac listing; both read "Can't
  check for updates" while the App Store listed their updates.
- An update from the App Store stays when a later answer, from a copy of Apple's catalog that isn't up to date yet,
  names an older version.
- An app only Homebrew can answer for, such as Visual Studio Code, no longer reads "Up to date" on what Homebrew knew
  days before: what Homebrew says counts for a day after it last checked for new versions, and the app's page then says
  when that was and that Update Homebrew lets Peel tell again. `peel updates` says it too.
- An update Homebrew learns of shows at once, also for an app it had called up to date.
- An app whose own feed couldn't be reached no longer reads "Up to date" on what Homebrew knew more than a day before,
  or once Homebrew no longer has the app, and its feed is asked again as often as any feed that fails.
- An update an app's own feed found stays when a later check can't reach the feed, even where Homebrew, not caught up
  yet, calls the app up to date.
- An update Homebrew no longer reports leaves the list as soon as Peel reads Homebrew again, rather than a day later.
- Applications and `peel updates` no longer check an app from Setapp against the feed of the version its maker sells
  directly, which its bundle may still carry: Setapp keeps it current, and the app's page says so. What an earlier Peel
  answered about it is forgotten at once.
- A folder named like the app is no longer selected while another app's name holds that name, as Epic Games Launcher
  holds Epic: it is listed as also used by that app.
- An app whose identifier a tool wrote for it, such as Electron's `com.electron.<name>`, no longer lists every other
  such app's files for review.
- The files of another app of the same maker that macOS knows, such as a build Xcode keeps, no longer show on an app's
  page.
- Reset offers the settings of an app's own helpers also when the app's identifier names no maker, such as
  `md.obsidian`.
- A Homebrew cask that names the app and quits the app's own helper is believed also when the app's identifier names no
  maker, such as `md.obsidian`, so the paths the cask names show on the app's page and in `peel leftovers`.
- Showing the page of an app macOS doesn't know yet, such as one in Downloads, no longer registers it with Launch
  Services: Peel draws its icon from the app's own files.
- While a removal of many items goes on, Peel reads again, once a second, which programs hold a file open, so a file an
  app opened meanwhile stays where it is.
- The folders an app names after the last part of its identifier, its name with a version right after it, are found too,
  such as Folx's `Folx3` folder and log and iTerm2's folder in Application Support.
- An app's page, `peel leftovers`, and `peel uninstall` no longer say Peel couldn't look inside a folder named by
  another program's identifier, such as Microsoft AutoUpdate's cache in `/Library/Caches`: it holds nothing of the
  app's.
- An app named like something macOS keeps for its own services, such as `Knowledge` in Application Support,
  `GeoServices` in Caches, `Assistant` in Logs, or `Logging` in `/Library/Preferences`, no longer takes it: the app's
  page, `peel leftovers`, and `peel uninstall` leave it to macOS, whatever a Homebrew cask names.

#### Orphaned Files

- The folders a Spring Boot server's embedded Tomcat leaves in the temporary folder, named `tomcat.` with the port and a
  number, are no longer taken for apps' files, each listed as a gone app of its own.
- The folders macOS keeps for its own services, such as `ApplePushService` in `/Library/Application Support`, are no
  longer named among the folders Peel couldn't look inside, in Orphaned Files or on an app's page: only macOS reads
  them, and no other app's files are there.
- Something macOS keeps for its own services is no longer listed once an app of the same name is gone, such as
  `Application Support/Knowledge` after an app called Knowledge.
- Lists what an app with a tool's identifier left while another such app is installed.

#### Orphaned Files and Storage

- With many pages selected, the Move to Trash question no longer runs past the bottom of the screen and takes its
  buttons with it: it names the first few pages and counts the items of the others, which "Selected on N pages" lists.
- The Select menu in the toolbar of Orphaned Files, Space, Developer, Build Artifacts, and Installers opens the first
  page it selected on when no page is open, so what it selected shows, with Move to Trash, rather than nothing changing
  until a page is chosen.

#### Space

- App Caches no longer selects what macOS keeps there for itself under a plain name, such as the picture of your Apple
  Account or Setup Assistant's cache, and Hidden App Caches leaves out two more of macOS's own audio services.

#### Duplicates and File Search

- What they move goes as one removal, so a run that was interrupted shows in History as one interrupted removal.

#### `peel`

- The command `peel uninstall` offers to copy works for an app whose name begins with `-` or `=`: the name comes last,
  quoted where a shell would read it otherwise, and after `--` when it begins with `-`, so it isn't read as an option.

### Security

- Every folder on the way to a place Peel searches, such as `~/Library/Audio`, is refused whole, by the app and by
  the helper, so what is inside it can't go as part of its folder. A browser's own data folder still goes with the
  browser.

## 1.1.0 (2026-10-14)

> [!IMPORTANT]
> Peel 1.0.1 can't install an update itself. To update from it, quit Peel, move it from Applications to the Trash,
> and drag the new Peel into Applications: your History, exclusions, and settings stay. If Homebrew installed it, run
> `brew upgrade --cask peel` instead. If Home then says the helper isn't answering, choose Repair. From 1.1.0 on,
> Peel updates itself when you choose Install Update.

Peel now updates itself, sets apart what only an administrator can remove, and protects more of what nothing could
bring back, from files that sync to your other devices to chats and game saves. It finds more to clean, shows how far
along a removal is, and says within seconds when its helper isn't answering.

### Added

- **Updates:** Peel updates itself, through Sparkle. Choose Check for Updates in the Peel menu, or Install Update
  in About Peel when it says a new version is out; while Check for app updates is on, Peel also looks once a day. It
  shows what is new and installs the update only when you choose, once it has checked that it is signed as Peel's. A
  copy Homebrew installed updates itself the same way, and `brew upgrade --cask peel` still works.
- **Tweaks:** On macOS 27, Privacy has an Apple Intelligence section whose rows open the place where macOS keeps each
  feature's switch, as Apple's guide names it. Peel changes none of them.
- **Removals:** Says when an audio driver Peel moved stays loaded until you restart your Mac.
- **History:** On macOS 27, says under an audio driver in the Trash that it loads only after a restart once put
  back, and under an app that it shared its storage with another copy.
- **Applications:** Lists and uninstalls apps whose Info.plist names no identifier, such as OpenShot Video Editor.
- **Applications:** Move to Trash shows which app it is waiting for to quit and how many items have moved, on an
  app's page and on several apps' page.
- **Applications:** On several apps' page, a button jumps to each list.
- **Applications:** On macOS 27, says after an uninstall when macOS will still start the app's background items from
  the Trash, with a button that opens Login Items & Extensions, and `peel uninstall` says it too.
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
  on a Mac with Apple silicon, never their folders, and doesn't recommend a log written in the last 15 minutes.
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
- **iCloud Drive:** Shows downloads in the folders Finder shows them in, the biggest first, with a checkbox for each
  folder.
- **iCloud Drive:** Says how many downloads it leaves out because another copy on this Mac shares their space, and on
  macOS 27 counts the files Remove Downloads frees and lets you stop it.
- **Background Items:** On macOS 27, offers Remove for a job a deleted app left loaded, and says when an item runs
  from the Trash.
- **Command line:** `peel orphans` lists apart what needs an administrator, as `forAnAdministrator` in its JSON, and
  says when a match is only a hint; `peel uninstall` says how many items stayed for an administrator; and
  `peel apps --json` writes `null` for an app with no identifier.

### Changed

- **Safety:** Never moves anything that syncs to your other devices: besides iCloud Drive, now any file iCloud keeps
  in step, such as on a Desktop kept in iCloud, anything in a folder Syncthing, Resilio Sync, Synology Drive, or MEGA
  keeps in step, and the records iCloud keeps to stay in sync, from any page or from `peel`.
- **Safety:** Holds back more of what may exist only on this Mac, as it already did local mail and message history:
  WhatsApp's chats, Steam's game saves, Postgres.app's data folders, OBS's scene collections, and the backups an app
  keeps. They're listed with the reason, and you can still select them.
- **Safety:** When you uninstall an app, never offers a folder another installed app keeps its data in, or what one
  of Apple's packages installed. Build Artifacts never offers a Godot project's export credentials, and Space keeps
  the folder crash reports are saved in and offers only the reports, while History still puts the folder back if
  Peel 1.0.1 moved it.
- **Safety:** Never selects for you a launch job that runs another installed app's program, Chrome's native messaging
  folders while Brave reads them, or a folder holding a Solana program's key.
- **Safety:** Knows more browser wallets: Jupiter, Gate, NC Wallet, Wombat, Glow, and Wigwam in Chrome and the
  browsers built on it, and Station, Pontem, and Glow in Firefox. A browser profile that holds one stays whole.
- **Safety:** The helper's record of what it moves reaches the disk before it moves anything, and History right
  after a removal, so a power cut can't lose the way back.
- **Helper:** Says within seconds, even while Peel is busy, when the helper isn't answering, instead of after two
  minutes, and Home offers Repair. Home and Settings say Installing…, Repairing…, or Uninstalling… while it changes,
  and Home's other rows no longer wait for it.
- **Terminal:** The switch that reuses ssh connections says to leave it off with two accounts on one server.
- **History:** Names a reset and a saved copy of settings as what they are, and the Edit menu says Undo Reset.
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
- **Applications:** On several apps' page, the two options sit side by side above the lists.
- **Package Receipts:** Leaves for you to choose a folder a package made that something else has filled.
- **Space:** Holds back a cache something wrote to in the last 15 minutes, and keeps an update an open app downloaded
  until the app quits.
- **Developer:** Lists Dart's package store as installed packages, never selected, since every Dart and Flutter
  project builds from it.
- **Build Artifacts:** Holds back a build folder Git tracks, reading the repository's own index: Peel never runs Git
  in your project.
- **Build Artifacts:** Never selects a Meson build folder, wherever it is and whatever its name, since it keeps the
  options it was set up with: 1.0.1 suggested the ones Meson tags as a cache.
- **Build Artifacts:** Refuses to search a folder where apps and tools keep what they install, such as an editor's
  extensions.
- **Duplicates:** Copies with different Finder comments are no longer duplicates.
- **iCloud Drive:** Lists only what Finder shows, the Documents of each app's folder, never the data an app keeps
  beside them.

### Fixed

- **Tweaks:** The screenshot folder can no longer be the Trash, and a folder screenshots can't be saved in says why.
- **Terminal:** The Git tab leaves a setting to a file your settings include, so Peel's value never wins over yours.
  Keep key passphrases in your keychain no longer stops an ssh installed from elsewhere, such as Homebrew's, which
  doesn't know `UseKeychain`, and delta's lines on the Tools tab turn on the line numbers its description promises.
  The Shell tab finds the `.zshrc` zsh reads when your `~/.zshenv` moves zsh's files with `ZDOTDIR`.
- **History:** Put Back brings a file a Homebrew cask or an installer receipt named back under the name the disk
  gives it, registers an app it brings back with macOS, and judges with your exclusions as `peel restore` does. Undo
  now stays off, as Put Back already did, while History or the exclusions can't be read.
- **Settings:** The copies of settings a reset saves are now listed, and putting one back leaves an excluded app
  alone.
- **Settings:** App Folders refuses the Trash, so apps there no longer count as installed.
- **Helper:** A failed change of the helper is said once, where it was asked for, and Settings says Checking… until
  the helper has answered.
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
- **Orphaned Files:** A file is listed once however many places reach it, and the settings a running background job
  keeps beside its file are no longer listed.
- **Package Receipts and Homebrew:** Forget Receipt, Forget Cask, and Forget All turn off while History or the
  exclusions can't be read, as every other removal does.
- **Homebrew:** A cask whose packages are all gone joins the casks already gone and can be forgotten, and an excluded
  app also stops `brew uninstall` of a cask installed from a package.
- **Space:** The command that deletes outdated simulator runtimes shows only where the simulator tool knows it, and
  an area whose folder Peel can't list reads Unknown instead of leaving the page.
- **Developer:** An app whose name holds a bracket or a star no longer has another folder's caches listed as its own.
- **Build Artifacts:** A repository no longer reads as one project per package: what a build leaves deep in a
  project, such as Python's `__pycache__` folders, is grouped under that project.
- **Build Artifacts:** A folder holding only build output no longer reads as too large to date.
- **Build Artifacts:** A project's Time Machine switch turns off again, and keeps in backups the folders Peel holds
  back, such as one with a wallet, a key, or a repository inside.
- **Selections across pages:** An item selected on two pages counts and moves once, instead of counting twice and
  failing on the second page.
- **Duplicates:** A disk's own Trash is never scanned, and the files of a chosen folder offered whole aren't offered
  again.
- **iCloud Drive and Duplicates:** Never look into a folder that lives only in the cloud, which made it download.
- **iCloud Drive:** Names each app's folder as macOS shows it.
- **Scans:** Build Artifacts and Intel Software no longer skip the folder that comes right after certain files, which
  hid recent edits and Intel programs.
- **File Search:** No longer lists what syncs to your other devices.
- **Background Items:** No longer calls an app's login item or agent orphaned because `launchctl` names no program
  for it.
- **Remove Peel:** Ends Peel's Finder extension, which no longer offers Uninstall with Peel once Peel is gone, takes
  no step while Peel itself can't move, no longer waits minutes for a helper that can't start, and says what stayed
  in your language.
- **Finder extension:** Its copyright in Get Info is in your language.
- **Command line:** `peel restore` lists only what can go back and says why each other item stays, and
  `peel inventory` and `peel updates` know the apps a cask installed from a package.
- **Every language:** Each of the 17 translations was read again, sentence by sentence, so it reads the way the
  language does, in macOS's own words.

### Security

- Only an administrator can install, repair, or uninstall Peel's helper. Before, a standard account could uninstall
  it for every administrator of the Mac.
- A launch job's file, or a browser's native messaging manifest, can no longer mislead Peel through a program path
  that hides a NUL character.

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
