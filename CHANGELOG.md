# Changelog

Every release of Peel is listed here, newest first. The version is the one About Peel shows, and each entry groups
its changes the way [Keep a Changelog](https://keepachangelog.com/) suggests.

## 1.3.0 (not released yet)

### Added

#### History

- An item's row shows its whole path on hover, and its Control-click menu copies it, for an item in the Trash or gone.
- The Not Moved list has Start Over when it can't be read, as History has.
- History says once, above its list, how many older removals it no longer lists, and that what they moved is still in
  the Trash.

#### Settings

- Hide from the Dock while no window is open, under Show in Menu Bar: Peel's icon leaves the Dock with its last window
  and comes back when you open Peel again from the menu bar, Finder, or Spotlight.
- Under Watch the Trash and the disk warning, Settings says when macOS doesn't let Peel send notifications, with Open
  System Settings.
- On a standard account, Settings gives a line to add to `~/.zshrc` that runs Peel's own `peel`, with Copy.
- Uninstall Helper is offered while the helper waits for approval too, and asks first, since the helper serves every
  account.

#### Intel Software

- Java runtimes built only for Intel, in `/Library/Java/JavaVirtualMachines` and the same folder in your home.
- When Rosetta isn't installed, every kind but an app offers Apple's command that installs it, to copy, since only an
  app opening asks for it.
- A plug-in's page has Review in Plug-ins, and a background item's Review in Background Items, which open that page
  on the item, even when the page is off in the sidebar.
- On Apple silicon, a universal app that asks macOS to open it as Intel is listed, and says so. On macOS 27 the empty
  page points to System Settings' list of Intel-based apps.

#### Package Receipts

- Each package shows the name macOS gave it, and the search finds it by that name and by where its files are.
- Receipt Only lists the receipts whose package left nothing, with Forget All: one question, one removal, one entry in
  History.

#### Homebrew

- Before Upgrade, Upgrade All, Upgrade with Homebrew, and Uninstall, Peel quits the cask's app, with Force Quit after a
  while, and opens it again after an upgrade.
- Quitting Peel while Homebrew changes something waits for Homebrew; during an upgrade it asks first, with Keep Peel
  Open or Stop and Quit.
- A cask whose upgrade was stopped, its app left in Homebrew's folder, says so on its page, with the command that
  reinstalls it to copy.
- When Homebrew belongs to another account of the Mac, the page says so and Peel doesn't run its `brew`, which that
  account could change. One this account can only read, such as one root owns, keeps the lists, Check Health, and
  the vulnerability scan.
- The page says when Homebrew run from Peel doesn't read the `brew.env` your shell has it read, and where to put what
  it should follow.

#### Build Artifacts

- Any folder holding the `pyvenv.cfg` of a Python environment beside a Python project is listed as an environment, and
  never selected.

#### Duplicates

- The toolbar has a Select menu, with Select Recommended and Deselect All.

#### File Search

- When Spotlight doesn't index a disk the search reads, the page says so and names it, as `peel search` does.
- What a search found and left out is counted by reason, above the list, or in place of No Results: what syncs to
  your other devices, what you excluded, what sits where Peel moves nothing, and what macOS kept Peel from.
- The Filters button fills while a filter narrows the search, and No Results offers Clear Filters.
- A selected file a newer search leaves out stays selected, and a line above the list counts them, with Keep Selected
  and Deselect.
- On macOS 27, a row shows the day its file was modified.

#### Background Items

- A job whose file is gone, and one loaded from a file outside the folders launchd reads, can be stopped.
- A disabled job that still runs reads "Disabled, still running".
- A job its app gave launchd itself, such as an update's installer, says so, and the empty list says where apps set to
  open at login are.

#### Extensions

- An extension's page has Review in Applications, which opens its app's page, and a system extension shows its
  version, with the version that replaces it while macOS updates it.

#### Plug-ins

- A plug-in's page says which app it came with, installed or gone, and the question before a move names that app.
- Camera plug-ins in `/Library/CoreMediaIO/Plug-Ins/DAL`, which macOS loads only once legacy video device support has
  been restored in macOS Recovery, as the question before one moves says; an app's uninstall and Orphaned Files find
  them too.

#### Moving to the Trash from several pages

- When open apps keep part of what is selected, the alert names them all and offers Deselect Them, which deselects
  only the parts they keep, and Move the Rest, which moves the other parts after the usual question.

#### `peel`

- `peel history` says, where its list reaches History's oldest removal, how many older removals History no longer
  lists, and how many removals of its time left items behind.

### Changed

#### Home

- While the helper waits for approval, Home says to allow Peel in System Settings under Login Items & Extensions, as
  it is listed there.
- On a standard account, Command Line says Needs an administrator, without the command, in Settings too.
- The totals read Items moved and Apps moved, which is what they count, and the Mac's picture says it shows About in
  System Settings.
- About says that Homebrew's own uninstall and Clean Up delete what they remove.

#### Menu bar

- Before anything moved, the panel says Nothing moved to the Trash yet in place of zeros, its dates are in the
  secondary gray, and Space's line counts its areas without adding them up.

#### History

- A removal from several pages is named by its first four pages and how many more, in the app and in `peel history`.
- Forget says what it does: History stops listing the items, and nothing on the Mac changes.

#### Settings

- The note under Check for app updates says that with it off Peel doesn't look for its own updates either.
- Privacy says all that PRIVACY.md says of each address: a tap added from another address, a package built from
  source, the release notes in your language, and what a `brew.env` file can change.
- App Folders refuses a whole disk, macOS's own folders, all of `/Library/Application Support`, and a folder in a
  cloud, each with its reason.
- The Helper tab names every order the helper takes, and Remove Peel's notes name everything Peel's folder holds and
  what Homebrew's zap also does.
- App Folders gives each reason it refuses a folder a sentence of its own.
- App Folders takes a folder deeper inside an Applications folder than Peel looks, such as the one Unity Hub keeps
  its editors in.
- Sidebar is the first section of General.

#### Applications

- A row moves up to Updates Available once a round of checks ends, rather than while you read the list.
- Up to date says in its help when Peel last checked, and while the checks are off an old Up to date isn't shown.
- Forget Receipt is in the More menu of an app's page.
- An uninstall lists an app's audio plug-ins unselected, since music apps load them on their own.
- An app with an update waiting shows it in a panel of its own under the app: the version, how to get it, and the start
  of what is new. Show More… opens all of it in a popover, where a long changelog scrolls.

#### Orphaned Files

- A group holding an audio plug-in reads unsure, since music apps load it on their own.

#### Intel Software

- The page says that this copy is built for Intel only, and to install the maker's version for Apple silicon when it
  offers one, rather than that no other version exists.
- It says where an Intel plug-in can still load, and on macOS 27 that an app set to open using Rosetta opens natively.
- A part inside an app says it comes with the app and that an update of the app may replace it.
- A plug-in installed in several formats says its format on each row.
- Nothing Needs Rosetta names the folders Peel read.

#### Homebrew

- Clean Up's and Update's notes say what else Homebrew deletes, and when Homebrew goes online on its own.
- Forget's question names the folders whose links go with a cask's Homebrew receipt.
- A cask's notes open in full in a popover from Show More…, rather than unfolding on the page.

#### Space

- The groups are named Media and Library, for what they hold.
- An area Peel only explains says "Managed by its own app or tool", and above its commands that those that remove
  something delete it for good.
- Local snapshots are explained in Apple's words, and the page says when macOS can't delete some of them to make room.
- Podcast Downloads says its figure holds all the Podcasts app keeps.

#### Developer

- The page says it lists browsers' and Electron apps' caches too, and how much of what it found Peel recommends, and a
  tool's list is headed Folders.

#### Build Artifacts

- A project's page says that nothing is selected for you, and names Select Recommended.
- Two projects in folders of the same name are told apart by the folders above them, everywhere they are named.
- A Git index that took too long to read says so, apart from one Peel couldn't read.

#### Installers and Backups

- An installer is judged by the address it says it came from: one that names none and is no installed app's is held
  back wherever it is, and so is one that arrived in the last hour.

#### Duplicates

- Scan Settings' Folders note says what a folder comparison leaves out, and why.
- Copies are grouped by their bytes: the copy whose tags, comment, or resource fork the others lack stays, marked
  Stays, and every other copy is suggested.
- The copy on the home folder's disk is kept before one on another disk, even an older one or one outside Downloads,
  and the cloud shows only beside a copy that syncs through one.

#### iCloud Drive

- The page starts on only where iCloud Drive is set up, and says when it isn't.
- A download in an app's own iCloud folder is listed and not recommended, and the page says that iCloud keeps a copy
  of what it uploaded and that files open again only online.

#### File Search

- Files are sized by what moving them frees, and one that frees less than its length says so; `peel search --json`
  gives both.
- A file in a repository or in `/Users/Shared` is listed and not recommended, and the Filters note says what a kind
  is.

#### Background Items

- An excluded app's jobs stay listed, marked Excluded in Settings, and Peel acts on none of them.
- A job macOS hasn't listed yet reads Not listed in System Settings yet.

#### Extensions

- The points an extension plugs into are named as System Settings names them.

#### Every page

- The helper's banner says what the page needs it for, moving how many items, forgetting the receipt, or changing the
  job.
- Peel knows two more browser wallets, Hana Wallet and Portal DEX in Chrome and the browsers built on it: a browser
  profile that holds one stays whole.
- What stays because a sync app keeps its folder in step names the app and the entry it keeps there, such as
  `~/.stfolder`, in a row's note, after Move to Trash, in History's Not Moved, for a folder Build Artifacts won't
  search, and under File Search's count, so an entry left behind by an app you no longer use can be found.
- The divider between a list and its page stays where it is and can't be dragged: without the sidebar, the list takes
  the room the sidebar covered.

#### `peel`

- `peel caches` and `peel projects` say why each folder stays, in their list, their JSON, and when `--remove` leaves
  it, and `peel duplicates` says why it didn't look in a folder.
- `peel orphans` heads each group with what `--remove` would move, and `peel leftovers` says when the app itself stays.
- `peel search` says which files it shows, that network volumes aren't searched, and at most how many it lists.
- `peel leftovers`, `peel duplicates`, `peel search`, and every refusal name the sync app that keeps a folder in step
  and its entry, and the JSON of `peel leftovers` and `peel duplicates` adds `syncedBy`.

### Fixed

#### Home

- Reopen Peel is offered however Full Disk Access was turned on, and App Management is learned from a move only when
  an app of another developer moved.
- Home says when History keeps every move back, with Open History, rather than You're all set.
- The greeting follows the hour whenever Home appears, Open at Login follows Settings at once, and VoiceOver hears each
  permission's state with its name.
- No command that links `peel` is offered from a temporary copy of Peel or a read-only disk.
- A copy of Peel that didn't install the helper offers no Install, and the Helper row's note no longer says a second
  copy needs its own.

#### Menu bar

- The panel is never taller than the screen: what is between its head and Open Peel scrolls when it doesn't fit.
- Found's "2 hours ago" stays true while the panel is open, and Orphaned Files counts only its groups.

#### History

- Nothing moves while History can't be written, as on a full disk, and every page that moves things says so.
- A removal History couldn't record says so in its alert, and comes back from the journal as the removal it was.
- Undo says what it left behind wherever you are, and the Edit menu no longer offers to undo a removal put back since.
- The page that moved an item lists it again after a Put Back.
- Put Back says why an item stays: excluded since the move, a protected place, not in the Trash where Peel put it, a
  locked item or folder, App Management, or a folder that isn't there anymore, each with its step. `peel restore`
  says the same, and leaves out of its plan what only the helper can put back.
- An item on a disk with the same name as another, or one renamed, is found by its volume, not its name.
- An uninstall's Dock icons go back at once, each beside the icons it sat between.
- History is read again when Peel comes forward, never says Nothing Removed Yet while it can't be read, and keeps
  fewer removals rather than growing past what it reads back.
- What macOS reported is worded in your language in the app, and in English by `peel`.
- An emptied History says No Removals, and `peel history` that History lists no removals, once Peel has moved
  something.
- A removal from several pages cut short by a crash stays one entry, the part cut short named as its page.
- A removal's notes about a put-back audio driver and an app that shared its storage show on macOS 26 too.

#### Settings

- Remove Peel judges each of its files before gathering them, gives the one cause that holds when it can't move Peel,
  runs alone and is told wherever you are, waits for Homebrew's answer, and is off on an account that can't remove the
  helper.
- Starting over a list never writes an empty one over a list that reads, and every Start Over says whether it started
  over, also to VoiceOver.
- App Folders says its list can't be read as soon as a reading of the apps finds it so, and starting it over anywhere
  clears the notice on every page.
- The login item and the Finder extension read Checking until macOS answers, and the Helper tab says when another copy
  of Peel installed the helper.
- Check for app updates checks at once whichever tab turns it on.
- `peel exclusions` notes a path that isn't there yet and counts only what went on the list.
- A `brew` chosen in Settings that can't be run is never replaced by another, and a `brew` where Homebrew installs
  itself is run only by the chosen one's rule.
- Remove Peel says why it waits when Homebrew can't answer, or when a Homebrew on this Mac that Peel doesn't run
  holds Peel's cask, with Open Homebrew, and nothing else moves while Peel removes itself.

#### Applications

- Folders of apps are read each on a thread of its own within a time limit, so one that doesn't answer is named and
  no longer holds the whole list.
- A round of update checks no longer stops after apps leave the list, and a check made while the Mac is still offline
  after waking changes nothing.
- No update is offered through Homebrew to the version the app already has, a Homebrew package that Homebrew disabled
  or can't compare says so, and each waiting update is told of once, whoever found it.
- Each build of an app keeps its own answer, an empty App Store answer about a found update is believed only twice in
  a row, release notes that didn't come are asked again only after a wait, and an Electron app's release its updater
  won't offer this Mac reads as up to date.
- An app that stays recommends nothing, a locked app gets no privacy reset, and an app's page turns its actions off
  while it removes the app.
- An app's page, several apps' page, and the Reset sheet tell VoiceOver how their scan ended, and the question to quit
  apps fits what runs and what goes.
- An app's page, or several apps' page, that can move nothing tells VoiceOver why rather than Nothing found, and the
  list tells VoiceOver what it found only after the first reading and after Rescan, so a removal is followed by its own
  words alone.
- Export List of Apps and the counts take only the apps installed on this Mac.
- Folders where an app keeps what you made are listed and never selected, at an uninstall and in Orphaned Files: an
  app's backups, a code editor's unsaved files and local history, Sublime Text's data, Minecraft's saved worlds, a
  browser's saved passwords, and Things 3's to-dos.
- Waterfox's, Zen's, and Floorp's profiles keep saved passwords, as Firefox's does, so they are listed and never
  selected.
- LibreWolf's, Mullvad Browser's, and Tor Browser's profiles keep your bookmarks, and Tor Browser's the keys you
  added for onion services, so they are listed and never selected too.
- An app's receipt stays, unselected, while its package left more outside the app.
- An app you had already moved to the Trash in Finder can lose its Dock icon too, once the files it left behind move.
- An app you moved to another folder in Finder loses its Dock icon too when Peel removes it.
- An app with nothing to say under its name, no version and no date of last use, shows its name alone beside its icon.
- A version left blank in an app's Info.plist counts as none: the row shows no empty line, and the update check no
  longer counts every release as newer.

#### Orphaned Files

- Files named with a gone app's own identifier are listed whatever the identifier's shape, such as `md.obsidian`.
- This Belongs To keeps a whole group out, is read without writing, and says when it can't be read or saved.
- The files of an app on a disk that isn't connected stay out, and a folder Peel couldn't look into counts among what
  it couldn't read.
- Rows that wait for the helper leave the selection when it stops answering.
- A kernel extension removed by an administrator says to restart once it is in the Trash.
- A gone app's files are judged from when Peel saw it go, not from when it last read the list.

#### Intel Software

- Intel programs that start with an i386 slice, and the Intel updaters apps keep in their frameworks, are found.
- The page reads itself again when shown and when Peel comes forward, names what it couldn't read, and counts Intel
  code once though a job or a command runs it.

#### Package Receipts

- A folder is offered whole only when nothing inside it is missing from the receipt, and every item follows its app's
  rules, an app that uninstalls itself with its warning.
- A package placed by its own scripts is never called a receipt only, a package installed into an app offers the app
  itself, and one whose app is installed says Still installed and what forgetting it costs.
- The list is read again when a receipt changed elsewhere, and a receipt already forgotten says so.
- An excluded app's receipt is left alone here too.

#### Homebrew

- Peel asks Homebrew for its prefix and its Cellar, so the formulae you excluded are always kept.
- Uninstall and Upgrade wait until Homebrew's apps are known, and the copied commands keep the excluded formulae.
- Check Health runs Homebrew's whole check, the vulnerability scan says when it checked the current formula, and the
  counts read Unknown until Homebrew answers.
- Clean Up's question names the first four formulae, the password advice shows only when `sudo` asked for one, and the
  page's spinners end with Homebrew's work.
- Update Homebrew is offered above lists read before Homebrew's own definitions went.
- Homebrew's last check is dated by its definitions file too, so a Homebrew that read its API today isn't said to have
  checked a week ago.
- A notice Homebrew gave no detail for, such as Homebrew didn't say what is installed, shows its title alone, without an
  empty line under it.
- When Homebrew stops before writing a Brewfile, File > Export > Brewfile says why in your language.

#### Space

- An area partly measured reads Over its size, a folder Peel couldn't look into is a row left alone with its reason,
  and the total counts only what can move now.
- The disk band is read as often as Home's, both figures of an area's notice come from the same moment, and the plan
  is made again once an app it names quits.
- A folder an app opened since the plan is named in the alert, Peel's own folders are left alone, and Sandboxed App
  Caches holds back what was written in the last 15 minutes.
- Simulators counts the runtimes CoreSimulator keeps as cryptexes, and an area open on its page stays listed after a
  move leaves it small.
- Caches for All Users and Logs for All Users keep what a service wrote in the last 15 minutes, and a service's log
  folder, offering only its files.
- An area macOS refused in part is sorted and judged by what Peel saw, and one refused whole is listed last.

#### Developer

- Only Neovim's own cache is listed, every Zed channel and Adobe's video apps are waited for, and JetBrains' logs are
  one row per product.
- One tool per Electron app however many copies, Hex 2.6's cache, search by a folder's name, and rows counted as items.
- A CocoaPods clone of another repository and an Xcode workspace with no recorded opening are kept with their reason.
- A running Spring Boot server's folder stays while something listens on its port, and Homebrew's cache is found where
  `HOMEBREW_CACHE` moves it.
- Jan's models are found where Jan's own setting moved its data folder.
- An Xcode archive whose version is left blank shows its build alone.

#### Build Artifacts

- A Python environment tagged as a cache, a node_modules in `/Users/Shared`, and a tool's own Time Machine mark are
  left to you, and any repository, Git or another, makes a project.
- Build output is found however deep a project sits, and work in a folder named like an artifact counts.
- The page scans again once its scan is an hour old, and a suggested folder whose project changed in the last 7 days
  stays when Move to Trash comes.

#### Installers and Backups

- A downloaded update is no longer called installed, a `.part` another program writes is left unselected, and a disk
  image that is open right now is never suggested or moved.
- The figures count only what can move, device backups point to System Settings > General > Storage first, and a
  macOS installer leaves the selection when the helper can't move it.
- An excluded app's downloaded update is left out, and macOS installers are found in every app folder and under the
  name Install OS X.
- A macOS installer whose version is left blank no longer reads Version with nothing after it.

#### Duplicates

- Nothing is compared while the exclusions can't be read, and what is inside an app's document is never offered,
  even when its app is gone.
- A network volume that stops answering no longer holds Peel's threads, a stopped scan says so, and only groups with
  something to move are counted.

#### iCloud Drive

- Remove Downloads works while History can't be read or written, and no total shows before iCloud Drive is read.
- The list says why it isn't all of it, an excluded folder is skipped whole, files are named as Finder names them, and
  a search reads only what the rows show.
- A download Keep Downloaded keeps, a password database, and a wallet's keys are held back, and a download's note is
  drawn beside its row.
- Remove Downloads counts and offers Stop on macOS 26 too.

#### File Search

- TypeScript files are no longer listed as Movies, and a search stopped for new words leaves no old list behind.

#### Background Items

- A system extension's job and an app's registered item are left to System Settings, with the way there.
- Agents are read, stopped, and started in the launchd domain they run in, a versioned Homebrew service has its
  buttons, and two files that declare one job are told apart.
- An enabled job that leaves the list says why, the list is read again when shown and when Peel comes forward, and
  VoiceOver hears what an action left an item as.
- Unusual command looks at `/Users/Shared` and the account's temporary folder, and reads base64 only when the command
  decodes it.

#### Extensions

- Each extension says where it is really turned on and off, an excluded app's extensions are left out, and the page
  is read again when shown and when Peel comes forward.
- A system extension whose app is gone says the app is no longer installed, and is named once while macOS updates it.

#### Plug-ins

- The page names the folders it couldn't read, follows a plug-in folder that is a link, and names a plug-in, and a
  Quick Action, as Finder and the Services menu do.
- An input method in use gives the steps that free it, and a plug-in History can't put back says so before it moves.
- Before a Quick Look generator, an old Internet plug-in such as Flash, or a contextual menu item moves to the Trash,
  the question says that nothing loads it anymore, rather than that apps using it may stop working.
- A plug-in whose version is left blank shows no empty line under its name.

#### Moving to the Trash from several pages

- Duplicates' part moves last, so the copy it keeps stays even when another page selected it.
- What changed on a page while its question was open is named in the alert after the move.
- When nothing on a list is recommended, Return cancels Select All.

#### Every page

- A program another account has open, a build tool's daemon, and a script a running Node.js or Python process was
  started with are named, with the step that frees them.
- A Dropbox folder outside File Provider counts as syncing, so nothing in it moves.
- The folders Peel couldn't read are named, the first four and how many more, with Copy Details, and Full Disk Access
  is suggested only when macOS's privacy protection kept Peel out.
- A scan waits for macOS's question about your files, and a page shown again starts its own scan.
- Each page's to remove counts only what can be selected now, the helper's state included.
- A removal bigger than History can keep is refused before anything moves, naming how many it keeps at once.
- What moving a file frees is one rule everywhere, so Time Machine's local snapshots no longer make duplicates read
  Zero kB to free.
- A folder only named like an app, as an app's web data or cache can be, stays in place while a program reads it.
- Return closes an alert that reports what went wrong, rather than copying its details, showing a file in Finder, or
  deselecting what open apps keep.
- VoiceOver no longer says Move or Build, the actions macOS names some symbols by: it passes over a folder's symbol
  beside its name, hears Info or Warning for a notice whatever symbol it draws, and Not installed for an app listed in
  Settings that isn't on this Mac.
- Hiding or showing the sidebar moves only the sidebar: the page keeps its width and place, and the window its size.
- On macOS 26, with the sidebar hidden, the title bar no longer draws a band and a line across the list and the page.
- On macOS 27, while the sidebar slides back, the page no longer runs past the window's edge, and the toolbar's last
  buttons no longer move into its overflow menu for a moment.

## 1.2.1 (2026-10-25)

### Added

#### Duplicates

- Duplicates scans the folders that sync to your other devices too, such as iCloud Drive, what Desktop and Documents
  hold when they are in iCloud, and what a sync app keeps in step, and lists the copies it finds there without ever
  moving them: beside a copy on this Mac such a copy is marked Stays, with a Show in Finder button in place of its
  checkbox and Quick Look, and a group whose every copy syncs is listed under Synced to Other Devices. The note
  beside Copies says what Stays means. `peel duplicates` marks such a copy `stays` and lists it under `synced` in
  its JSON.

### Fixed

#### Home

- The picture of your Mac is sharp: it was drawn from a small rendition and enlarged.

#### Updates

- An update waits for Peel to quit even when Peel sits in a folder with accented letters in its name, and the
  Install on Quit button is translated into Ukrainian, Russian, French, and Spanish (Sparkle 2.10.1).

#### Applications and Storage

- In every table of what would be removed, the circled i at the end of a row sits level with the row's checkbox,
  kind, and size. Before, it dropped below them whenever the badge or the kind took a second line in a narrow
  window.

#### Duplicates

- A chosen folder Peel doesn't scan is named with why, in Scan Settings, when it is added, and with the result: it
  holds app data, is a package, is outside your home folder, is a repository, or isn't there. Before, every such
  folder counted as one Peel couldn't read, and the page asked for Full Disk Access even when Peel had it.
- On a group's page, the Quick Look button sits level with the copy's badge and size, not below them.

## 1.2.0 (2026-10-24)

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

#### Home

- Right after Peel updates itself, its helper no longer shows as not answering, and what only the helper can move
  is no longer locked, while the helper of the version before is still leaving: Peel waits for it to go, then asks
  again.
- The picture of your Mac keeps an even edge all around, with no pale smudge below a desktop Mac or a virtual
  machine's display.

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
- When Peel can't read the folder that keeps the saved copies of settings, Saved Settings says so, with Show in Finder,
  rather than not showing at all as if no copy were kept.

#### Applications

- An app whose folder of system extensions Peel can't look into is left to Finder, as one whose extensions Peel can
  name, since only Finder's move asks macOS to remove them; its page and `peel uninstall` say so.
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
  `GeoServices` in Caches, `Assistant` in Logs, `Logging` in `/Library/Preferences`, WebKit's `Databases`, or the
  cookie store `Cookies.binarycookies`, no longer takes it: the app's page, `peel leftovers`, and `peel uninstall` leave
  it to macOS, whatever a Homebrew cask names.

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

#### Homebrew

- Clean Up, the download cleanups, and Uninstall run nothing while Peel can't read Homebrew's Cellar, or can't look into
  a formula's folder in it for an app you excluded, and say so: Homebrew deletes old versions for good, and Peel
  couldn't tell it which formulae your exclusions cover.

#### Space

- App Caches no longer selects what macOS keeps there for itself under a plain name, such as the picture of your Apple
  Account or Setup Assistant's cache, and Hidden App Caches leaves out two more of macOS's own audio services.
- Logs no longer selects the logs macOS writes for its own services, such as Siri's in `~/Library/Logs/Assistant` and
  those named `com.apple.`: as App Caches does with macOS's caches, it lists them and leaves them unselected.

#### Duplicates and File Search

- What they move goes as one removal, so a run that was interrupted shows in History as one interrupted removal.

#### Background Items

- A job whose program sits in a folder your account can't open is no longer said to have nothing left to run, nor
  offered for removal, and Orphaned Files no longer lists its file: launchd starts a daemon as root, which reaches it.

#### `peel`

- The command `peel uninstall` offers to copy works for an app whose name begins with `-` or `=`: the name comes last,
  quoted where a shell would read it otherwise, and after `--` when it begins with `-`, so it isn't read as an option.
- `peel leftovers` and `peel uninstall` say that a file found by its name inside a folder of macOS's own, such as
  `SyncServices`, sits inside a folder that belongs to macOS or to another installed app, as the app's row says, rather
  than inside another app's folder.

### Security

- Every folder on the way to a place Peel searches, such as `~/Library/Audio`, is refused whole, by the app and by
  the helper, so what is inside it can't go as part of its folder. A browser's own data folder still goes with the
  browser.
- A folder with a folder inside that macOS won't let Peel list is refused, by the app and by the helper, since a photo
  library, a browser's wallet, or work an app keeps only in a cache may be in there, and its row says so. One only an
  administrator can move is left to the helper, which looks inside as root.
- While you exclude an app, such a folder stays even when only the helper could move it, since a folder of the app you
  excluded may be in there and the helper knows nothing of your exclusions; the Homebrew page doesn't run
  `brew uninstall` on a package with one.

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
