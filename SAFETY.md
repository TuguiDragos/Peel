# Safety

Peel removes files. So the question that matters most isn't whether someone can break in. It is **whether Peel can
take something you can't get back**, and this page answers it: what Peel never removes, what it never deletes, what
it changes besides moving files, what it selects for you and what it leaves to you, how it keeps crypto wallets,
how a reset stays within an app's settings, what it changes in Terminal's, the shell's, Git's, and ssh's settings,
and what its helper, which runs as root, may do.

In short:

- Everything Peel removes goes to the Trash, and History puts it back. Peel never empties the Trash.
- What nothing could bring back, such as iCloud Drive, keychains, crypto wallets, Mail, Messages, and photo
  libraries, is refused, whoever asks.
- Peel selects for you only what is certainly the app's and no other app's. What may exist nowhere else is shown
  with its reason and left to you.
- Nothing moves from under a program that is using it.
- The few things History can't undo say so before you confirm them.
- The helper that runs as root does a few things only, for administrators only, and checks everything again itself.

To report a way around any of this, see [SECURITY.md](SECURITY.md).

## What Peel will never remove

These folders are refused outright, wherever the request comes from: the app, the command line tool, or the
helper running as root. The list lives in `ProtectedData.swift`, beside the helper rather than in the app,
because a program running as root must not depend on its caller to tell it what is irreplaceable.

In the Library of every account on the Mac and, for the last rows, in the home folder itself:

| Folder | Why |
| --- | --- |
| `Mobile Documents` | iCloud Drive. A file removed here is removed from every device you own. |
| `CloudStorage` | Dropbox, Google Drive, OneDrive, and the rest. Same reason. |
| `Keychains` | Your passwords and keys. |
| `Passes` | Wallet. |
| `Spelling`, `KeyboardServices` | Words you taught the Mac, and your text replacements. |
| `Autosave Information` | Work an app has not saved yet. |
| `Application Support/MobileSync` | iPhone and iPad backups. |
| `Application Support/AddressBook`, `Contacts` | Your contacts. |
| `Application Support/CallHistoryDB` | Your call history. |
| `Mail`, `Messages` | Your mail and your messages. A Mail plug-in in `Mail/Bundles`, which holds code and no mail, may go. |
| `Safari` | Bookmarks, history, reading list. |
| `Calendars`, `Reminders` | Your calendars and reminders, where older systems kept them. |
| `Group Containers/` any of Apple's own | Where macOS 26 keeps notes, reminders, calendars, voice memos, the journal, and more. Apple moves these between releases, so they are recognized by their name (`com.apple.` after an optional team and an optional `group.`, `groups.`, or `systemgroup.`), not from a list. |
| `Shortcuts` and its two group containers, `HomeKit`, `Accounts`, `Finance`, `IdentityServices` | Your shortcuts, your home, your accounts and what they hold. |
| `Application Support/FaceTime`, `CallHistoryTransactions` | Calls. |
| `Containers/com.apple.freeform`, `com.apple.journal`, Stickies' notes, Safari's own store | Boards, journal entries, stickies, and tabs. |
| `.Trash` | Already-deleted things are not Peel's to delete again. |
| `.ssh`, `.gnupg`, `.aws`, `.password-store` | Keys, credentials, secrets. |
| `.android/debug.keystore`, `.m2/settings-security.xml`, `.gradle/gradle.properties`, `.git-credentials` | One key or credential each, named on its own so the cache around it can still be cleaned: the file stays, and so does any folder that holds it. |
| The keys of desktop wallets and key tools: Bitcoin Core's `wallets` and `wallet.dat`, and those of Litecoin, Dogecoin, Dash, PIVX, Firo, Namecoin, Groestlcoin, Elements, Liquid, and Zcash; Monero's `wallets` and MyMonero's; the Electrum family's, Sparrow's, Wasabi's, Ginger's, Specter's, Ashigaru's, Bitcoin Safe's, and JoinMarket's; Exodus's `exodus.wallet` and `Backups`; Atomic, OneKey, Frame, Rabby, Stack Wallet, BlueWallet, My Wallet, Umami, Bisq, Haveno, Bison Wallet, Liana, Nunchuk, and Green; geth, Clef, Foundry, Hardhat, Ape, and Brownie keystores; the validator keys of Lighthouse, Prysm, and ethdo; the Lightning nodes; Cashu's ecash; and the Solana, Sui, Aptos, NEAR, Stellar, Starknet, Fuel, Avalanche, Tezos, Cosmos, Osmosis, Cardano, Decred, Chia, Grin, Kaspa, and Nano key files, 121 places in all | Lose one and what it holds is gone unless its seed phrase was kept somewhere else. Each is named on its own, read from the project's own documentation or source, so the key stays, and so does any folder that holds it, while what comes back on its own beside it, such as a downloaded blockchain, can still go. |
| `.config`, `.cache`, `.local`, `.kube` and its `config`, `.CFUserTextEncoding`, your shell's settings and history (`.zshrc`, `.zsh_history`, `.zsh_sessions`, `.bash_history`, and the like), and the settings of git and other tools (`.gitconfig`, `.gitignore_global`, `.netrc`, `.npmrc`) | Shared by many tools and owned by no app. They are never removed themselves; what one tool keeps inside `.config`, `.cache`, or `.local` still can be. |

Outside your home: everything inside `/System`, `/usr`, `/bin`, `/sbin`, and `/Library/Updates`, where macOS
stages its own updates, but for two things: a link that leads nowhere, directly in `/usr/local/bin`,
`/usr/local/sbin`, or one of the four folders of `/usr/local` that shell completions are linked into, which an
app's tool or its completion leaves there once the app is gone and the helper may take, or Peel's own link to its
`peel` command, which Remove Peel hands the helper (see [The helper that runs as
root](#the-helper-that-runs-as-root)); and a folder directly in `/usr/local/Caskroom`, the record
Homebrew keeps of an app it installed on an Intel Mac, which goes with the app. And these folders themselves,
though not what is inside them:
`/`, `/Applications`, `/Library`, `/Users`, `/Users/Shared`, `/Volumes`, `/opt`, `/private` and its `var`,
`tmp`, and `etc`, `/cores`, your home folder, and every folder Peel searches, such as `~/Library/Caches`, which
is looked inside and never moved whole. Anything System Integrity Protection guards, which macOS marks as
restricted, is refused as well, and so is anything macOS marks so that nothing can remove or rename it, such as
the private folders it makes in your temporary folder for the processes it runs in a sandbox; Peel doesn't list
those.

Everywhere on the Mac: `/Library/Keychains`, and any `.photoslibrary`, `.photolibrary`, `.migratedphotolibrary`,
`.musiclibrary`, `.tvlibrary`, `.imovielibrary`, `.fcpbundle`, or `.aplibrary`: somebody's whole photo, music, or
video collection. A folder with one of them a level or two inside stays too, since moving the folder would take the
library along, and the row says so instead of failing when you press the button. A browser profile with a
wallet in it stays the same way, and so does a folder that holds one a level or two down: see
[Crypto wallets](#crypto-wallets).

Also refused: work that an app keeps inside a *cache* folder and nowhere else. A JetBrains IDE and Android
Studio record your unsaved edits in `LocalHistory`, beside their caches, and Deno keeps `localStorage` and its
key-value databases in `location_data`. Those folders, and any cache folder that holds one, stay: emptying
"App Caches" in Space leaves them where they are.

Also refused: a sandboxed app's own `Data/Documents`, which is where that app keeps *your* work, not its
settings. The rule holds for the folder around it too: while `Data/Documents` holds anything, or cannot be
read, the app's whole container stays, and Peel shows it with the reason instead of selecting it. The folders
of every account's home (Applications, Desktop, Documents, Downloads, Library, Movies, Music, Pictures, Public)
are never moved themselves, though what you choose inside them can be. Neither are the files of the global
preferences domain (`.GlobalPreferences.plist` and its twins): your language, keyboard, and scrolling settings,
which belong to no app.

### How the check can't be tricked

**The check is not a string comparison.** A disk is case-insensitive unless you went out of your way, so
`~/Library/mobile documents` is the same folder as `~/Library/Mobile Documents`; `/var` and `/private/var`
are one folder with two names; and a symbolic link in any parent gives a third. All of those spellings are
folded together before the check, and there are tests that try to get past it by each route.

**A name is not the thing.** macOS also reaches a file through names no list of spellings contains: a path can
follow `/.nofollow/` or `/.resolve/0/`, and `/.vol/<device>/<inode>` reaches a file by its numbers alone. The usual
way of resolving a path folds none of them, and the Trash takes a file under each. So Peel asks the system what it
calls the item, from an open descriptor rather than from the text, and asks the disk what the item *is*. The places
the table names in your home, `/Library/Keychains`, and each folder that stays itself are known by their device and
inode as well as by name, wherever a link leads them, and an item is refused when it, or any folder it really sits
in, is one of them. That also catches a file name that begins with a combining accent, whose start a text
comparison can't see. Every other rule on this page judges an item by its names: as written, where it really sits,
and as the system names it, spelled as the disk stores it.

**The thing judged is the thing moved.** A check made by name and a move made by name are two looks at
the disk, and between them a folder can be swapped for a link into Messages by anything running as you. So
Peel holds the folder open, asks the question again about the name the system gives that open folder, and
moves the item through it: whatever the old name leads to by then is not touched. Putting an item back
holds the folder it returns to in the same way. The cost is that Finder's own Put Back does not know these
items, since only Apple's by-name call writes the note Finder reads; Peel's History puts them back, and in
Finder they can be dragged out. One move still goes by name, the first ever made on a disk, because that
call is the only thing that makes a disk's Trash. What it moved is then compared with what was judged, and
a difference is reported instead of recorded.

The place Put Back writes to does not exist yet, so asking the disk about the file itself answers nothing. Peel
asks about the deepest folder on the way that does exist, with every link resolved, and gets back the name
the disk really uses. That also covers the letters a Mac's disk treats as the same (`ß` for `ss`, the long
`ſ` for `s`), which no lower-casing undoes. An item is judged where it sits, not where it points: moving a
link moves the link.

## Nothing of yours is deleted permanently

Peel never deletes anything of yours. Everything it removes goes to the Trash, and everything is recorded so
History can put it back; History keeps the most recent 20,000 items, and what it forgets is still in the Trash.
The space is freed when *you* empty the Trash: Peel never does that for you.

That includes what other tools would delete:

- An installer receipt you ask Peel to forget: the two files that make it up go to the Trash through the helper,
  where `pkgutil --forget` would have discarded them for good.
- The folder Homebrew keeps for an app it installed (`brew --caskroom`), with the links Homebrew made into it,
  which `brew uninstall` would delete: they go after the app, Homebrew stops listing the app, and History puts them
  back. The Homebrew page forgets the same way a cask whose apps are already gone, which Homebrew still lists and
  can't upgrade: its folder and the links into it, or into its gone apps, go to the Trash.

A removal reaches History even when something cuts it short. Quitting Peel waits until History has it, `peel`
carries on through Ctrl-C or a closed terminal until it has written History, and each item is written down the
moment it moves, so one cut short by a crash or Force Quit still reaches History, as an interrupted removal, the
next time Peel or `peel` opens it.

Right before anything moves, Peel looks at the files other programs of yours hold open and at the program each
process runs, and leaves where it is any file or folder with one of them inside, naming the program: moving a
database or a cache from under an agent, a daemon, or a server that is using it would break it. An app is code,
which loses nothing when it moves, so a program that only reads inside it, as Safari reads an app's Safari
extension, does not keep it in place; one that runs from it or writes in it does, unless the app uninstalls itself
once it is moved, as Mullvad VPN does: the program running from it is the one that cleans up. Peel itself counts
too: whatever Peel runs from, and any folder holding it, stays, since only Remove Peel moves Peel. Of programs that
run as another account or as root, macOS's own among them, only the program can be seen, never the files it holds
open, which is why Space also leaves macOS's own caches unselected, and in the Library at the top of the disk, where
those programs keep theirs, does not list them at all. Neither you nor Peel can quit such a program, so Peel never
asks you to: what it runs from stays, and says so, until it is stopped in Background Items or by the app's own
uninstaller.

A move to the Trash, or back from it, never replaces what is already at the new name. Most disks refuse that by
themselves; on one that cannot, such as exFAT, Peel first takes the name with an empty placeholder, which only a
free name allows, and the move then replaces the placeholder.

What Peel deletes outright holds nothing of yours: such a placeholder, when the move it was made for fails; the folder
it makes to save an app's settings before a reset, when saving fails before anything is written in it; and the empty
settings file macOS writes back when Peel forgets a preference domain, as described below. Its list of refusals goes
to the Trash when `peel history --refused --clear` is asked to forget it, after a question.

Four things Peel starts can't be undone by History, and Peel says so before you confirm each of them:

- Homebrew's own uninstall and its clean ups (Clean Up, and clearing older or every download), which delete what
  they remove. An upgrade from the Homebrew page never cleans up on its own, although Homebrew would by default; if
  one of Homebrew's own settings files (`brew.env`) turns that cleanup back on, the Homebrew page says so and Peel
  leaves upgrades to Terminal.
- Resetting an app's privacy permissions, which is off until you choose it.
- Force Quit, which Peel offers when an app it has to quit is still open after 10 seconds, and which loses what that
  app had not saved.

Forgetting a preference domain after a removal is not one of them: it happens only once the file is in the Trash,
and putting the file back undoes it, until the app writes its settings again.

One app deletes something of its own once it is moved: Mullvad VPN's service logs the Mac out of its account and
deletes its settings when the app leaves the Applications folder, which Peel says before it moves it. What that
service removes (its launch daemon's file, its command links and shell completions, its receipt, its logs, and its
settings) is listed and never moved by Peel: moving the daemon's file first would stop the service before it could
clean up.

If the record itself is damaged, it is set aside under another name rather than overwritten, because it is
the only way back from a removal. If it can't be read at all, Peel moves nothing until it can, or until you
start it over in History, which keeps the old file beside the new one: what moved meanwhile couldn't be put
back. The `peel` command says so and moves nothing either.

The record is also a file any process running as you can rewrite, so Put Back reads it as a request, not as
a fact. It only takes something that really sits in a Trash of yours (`~/.Trash`, or `.Trashes/<uid>` at the
root of another disk), asked of the folder itself with every link resolved: a folder that is merely called
`.Trash`, a link into Messages, or iCloud Drive's own Trash, is refused. And it takes only the very item that
went: History keeps which item it was (its inode and when it was made), so once the Trash is emptied, another
item that lands in the same place, another project's `node_modules`, say, is never put back in its stead.
History offers to forget a record only once its item has certainly left the Trash, asks first, and looks again
just before; an item Peel isn't allowed to look at is shown as not known and kept.

## What Peel changes besides moving files

Some of what Peel does is not a move to the Trash. Each is here with how it is undone.

| What Peel changes | How it is undone |
| --- | --- |
| A preference domain is forgotten (`defaults delete`) once its file is in the Trash | Putting the file back from History, as described below |
| A launch job is stopped (`launchctl bootout`) once its file is in the Trash | Putting the file back from History, which starts the job again (`launchctl bootstrap`, a daemon through the helper) |
| An uninstalled app's icon is taken out of the Dock, which restarts the Dock | Putting the app back from History puts its icon back where it was |
| An app's privacy permissions are reset, only when you choose it | Can't be undone: the app asks again for each permission |
| Homebrew uninstalls a package or cleans up its downloads | Can't be undone: Homebrew deletes what it removes |
| An app that would not quit is force quit, only when you choose it | Can't be undone: what the app had not saved is lost |
| Remove Downloads frees this Mac's copy of a file in iCloud Drive | The file stays in iCloud and downloads again when you open it |
| Build Artifacts leaves a project's build folders out of Time Machine, when you ask it to | The same checkbox takes the mark off |
| A background item is stopped, started, disabled, or enabled | The same buttons in Background Items; a disabled item stays disabled after a restart until you enable it |
| A tweak changes a setting of macOS, and the Dock, Finder, Control Center, or the window manager restarts to read it | Turning the tweak off, or Turn All Off, puts back what was there before, or leaves it to macOS |
| The Terminal page adds Peel's profiles and options to Terminal, makes `~/.hushlogin`, writes Peel's shell and ssh files, and changes Git's settings | Put Back, turning the setting off, or Turn All Off, as [Terminal's settings](#terminals-settings) says |

The first three happen after a move, and only for what really moved:

- **A preference domain is forgotten** (`defaults delete`), or macOS could write the file again from memory. While
  macOS still holds the domain, as it does for a moment after the app quits, it answers by writing the domain back,
  empty, where the moved file was. Peel deletes that file, which holds nothing, so History can put the real one back:
  only when nothing was at that name before, the file is yours, and it holds no setting at all. Otherwise macOS
  answers that the domain is not found and changes nothing. A file put back from History is read again at once, so
  History undoes it for an app that has not run since. It is done only for a file that went from your own
  `~/Library/Preferences`, or, when you reset a sandboxed app, from the Preferences folder in its container. Never
  for the copy every account shares in `/Library/Preferences`, never while the app's container still holds its own
  settings, never for one of Apple's domains on another app's behalf, never for Peel's own while it runs, and never
  for the global domain under any of its names.
- **A launch job is stopped** (`launchctl bootout`), or launchd would keep it running and start it again. Putting
  the file back from History starts again the job Peel stopped, as the file back in place declares it (a daemon
  through the helper), and a job that was not running stays as it was.
- **An uninstalled app's icon leaves the Dock**, unless you deselect it, which restarts the Dock. Putting the app back
  puts its icon back where it was.

## What is selected for you

Only matches Peel is `certain` or `likely` about, and only when nothing else installed on the Mac uses them.

- **Shared means left unselected.** Anything another app uses is shown and left unselected, and so is what another
  copy of the app uses: one macOS knows anywhere, such as an older copy in Downloads or one on another disk, named
  by where it is. An app of the same maker kept outside the Applications folders, such as a Nightly build on another
  disk, counts like one inside them, and so does one Peel saw installed before: the files named for a Nightly you
  removed are its, not this app's, and Orphaned Files lists them under it.
- **A name alone is a guess.** Something matched by the app's name alone inside a folder named for neither the app
  nor its maker, such as another app's, one of Apple's, or a command-line tool's, is shown and never selected, since a
  folder of that name may be that program's own; so is something matched by name alone at the top of your home folder
  or of a Library, or in a maker's folder there.
- **A plug-in goes by what it declares.** Its name says what it does rather than who made it, so a plug-in called
  like the app is selected only when the identifier it declares is the app's or its maker's: another maker's plug-in
  with the app's name is never selected.
- **A system extension is left to macOS**, which uninstalls it itself when the app is deleted, so it is not listed.
- **An app that stays keeps its files.** Nothing at all is selected for an app that would stay: one macOS keeps, one
  that is part of another app, one the helper may not move, or one that needs the helper while it cannot act. An app
  that is part of another, such as a helper app inside the app it serves, is never moved on its own, from the app or
  from `peel`: it would be cut out of the app it belongs to. When you remove several apps at once and deselect one of
  them, it stays too: its files leave the selection, those it shares with the other apps included, and selecting it
  again brings them back.
- **An empty folder of the app's maker goes too.** A folder in your Library named for the app or its maker, such as
  `Application Support/<Maker>`, that an uninstall leaves empty goes to the Trash with it; one with anything left
  inside, a hidden file included, one with another name, and the Library folder itself stay.

A security or management agent whose maker documents removing it with an uninstaller of its own (GlobalProtect and
Cortex XDR, Cisco Secure Client, ESET Endpoint Security, Microsoft Defender, Netskope Client and FortiClient) is
listed the same way, and nothing of it can be selected: its page names the maker's uninstaller and links to the
maker's instructions, since moved from its place, what it keeps in the system and the settings that manage it would
stay behind. Peel knows it by the team its checked signature names and by its identifier, both as the maker
documents them, never by the identifier alone, which any app could claim. `peel uninstall` refuses it and names the
same uninstaller.

Peel itself is listed on its own page with what it keeps, and nothing of it can be selected there or among other
apps. It is removed only from Settings: by Remove Peel, which takes its helper and login item away first, or,
for a copy Homebrew installed, by the Homebrew command Settings shows in its place.

Never selected for you, even when found:

- Xcode's archives of the apps you built and the symbols it copied from your devices, both needed to read crash reports,
  and the reports macOS wrote when an app crashed, which its developer may still ask for.
- Model weights, the packages a tool keeps installed outside your projects, virtual environments, the installers and
  boxes a tool keeps for you to install again, and an editor's saved state for a project that no longer exists.
- A cache macOS keeps for its own services in `~/Library/Caches` (Spotlight's, iCloud's, the fonts') or in the container
  of one of Apple's apps.
- `/Users/Shared`: it belongs to every account, not just yours.
- A project you worked on this week, and a download that changed in the last day, which may still be going.
- A folder with a repository, a wallet, a signing key, or a password database (KeePass's `.kdbx`, KeePassXC's `.keyx`)
  inside.
- What an app keeps that may exist only on this Mac: local mail, message history, a password manager's backups and an
  authenticator's codes, VPN connections, a game's saves and a database, each where the app's own documentation or
  source says it keeps them, and anything named as an app's backups.
- A copy Mail keeps of an attachment you opened, which you may have changed.
- A file in iCloud Drive, which the Trash would take from every device, and a file a program has open right now.
- An installer package an app keeps in Application Support, which the app may still need, and an update whose app is
  running, which may install it when the app quits.
- An encrypted disk image, and a disk image, package, or archive outside Downloads that isn't an installed app's
  installer, which may be your own rather than something you can download again.

A folder macOS would not let Peel read, and a folder Peel could not measure in time, are not selected either. Both are
shown with their size as "Unknown", never as zero, in every tool and in History once they are moved: a folder too big to
read quickly may be exactly the one with work inside, and nothing is selected for you without saying how much it is. A
total that leaves such a folder out reads "Over" what is known.

A repository can still be selected in two places, since its tool makes everything there again. One is a folder its
tool tags as a cache (`CACHEDIR.TAG`): Swift Package Manager tags `.build`, where it clones a package's
dependencies, and `swift package reset` deletes that folder whole, so Build Artifacts can still select it. The other
is a cache on the Developer page, a folder its tool's documentation or source shows to be a cache, such as the
packages Xcode checks out into DerivedData or the clones Cargo and Swift Package Manager keep, which the tool clones
again when it needs them. Of Carthage's folder in a project, only `Carthage/Build`, which `carthage build` makes, is
offered: its checkouts, which people commit in, carry no such tag and are never listed.

Build Artifacts recommends what a build or a package manager makes again from the project's own files, such as
`DerivedData`, `.build`, and `.next`, once Peel can tell that nothing in the project has changed for a week. That
includes `node_modules` and `Pods`, which `npm install` and `pod install` put back from the project's `package.json` and
`Podfile`. A Python environment (`.venv`, `venv`) is listed and never selected, since packages are often installed into
one by hand, and so is Terraform's `.terraform`, which keeps the workspace you chose. A folder whose name says nothing
on its own, such as `target` or `build`, is listed and never selected either.

Developer, Build Artifacts, Space, and Installers and Backups select nothing for you: opening a page selects nothing,
and Select Recommended selects what Peel recommends there.

Orphaned Files selects nothing for you, and `peel orphans --remove` leaves these folders out as well: one in
`/Users/Shared`, one with a repository, a wallet, a signing key, or a password database inside, one that may hold what
exists only on this Mac, or one Peel could not read or measure in time, moves only when you select it yourself.

On every list, Select All selects every row you can select, what Peel holds back included, and asks first,
counting what Peel doesn't recommend; Return answers Select Recommended. Each held back row still shows its reason
beside it.

In Duplicates, one copy of every group always stays, and a file that changed since the scan is refused. Nothing
inside an app or another package is ever offered, nor a hidden folder, such as a tool's settings in `~/.config`:
they only count toward the folder around them.

What you select on the pages that free space (Orphaned Files, Space, Developer, Build Artifacts, Installers and
Backups, Duplicates, and File Search) stays selected while you look at the others, and Move to Trash on any of
them moves all of it. Only a page you have opened counts, so nothing moves from a page you never saw. Before anything
moves, the question lists every page with how much it holds, and each page's part is moved by its own tool, with
that tool's checks at that moment: Developer waits for its app to quit, Space leaves out what an app opened since
is writing to, and Duplicates refuses a copy that changed. What a tool refuses for the item itself, such as a folder
a program still has open, leaves the selection, so the next Move to Trash on any page does not carry it again.

Some things are shown and never removed at all, because the removal cannot be undone: local Time Machine
snapshots are explained, never deleted.

## Crypto wallets

A wallet's keys can be the only way to what they hold, so Peel keeps them in four ways.

- **Where wallets keep their keys is never removed.** The 121 places in the table at the top of this page, each
  read from the wallet's own documentation or source, are refused outright by the app, the `peel` tool, and the
  helper, and so is any folder that holds one. When a wallet's folder was moved to another disk and linked back,
  as is common once a blockchain outgrows the startup disk, its keys are refused there as well. What comes back on
  its own beside a key, such as a downloaded blockchain, can still go.
- **A browser profile with a wallet stays.** A wallet extension such as MetaMask or Phantom keeps its vault in the
  browser's profile, beside `Local Storage`, which every extension shares. So a profile that holds one of the
  wallet extensions Peel knows (those of more than 60 wallets, for Chrome, Brave, Edge, Arc, Opera, Vivaldi, and
  Firefox) or Brave's own wallet stays, and so does a folder that holds it a level or two down, which is where a
  browser keeps its profiles (`Google/Chrome/Default`): uninstalling a browser never takes its wallet. A profile
  whose extension storage macOS will not let Peel list stays too, since it is not known to hold no wallet. The rest
  of what a browser keeps, such as its caches, can still go.
- **A wallet found anywhere else is never selected for you.** When an uninstall, Orphaned Files, Space, Developer,
  Build Artifacts, Installers and Backups, or Package Receipts measures a folder, it also looks inside for the names
  wallets and key tools give their files: anything called `wallet.dat`, `wallets`, `keystore`, `seed.dat`,
  `hsm_secret`, or `channel.backup`, anything ending in `.wallet` or `.keys`, and the others `FileSize.isWallet`
  lists. A folder with one inside is shown with that reason and never selected for you, not by `peel uninstall`,
  `peel orphans --remove`, `peel caches --remove`, or `peel projects --remove`. You can still select it yourself,
  with its own click or with Select All once you have answered its question, because a name can mislead: a Java
  project keeps a `keystore` too.
- **A folder Peel could not finish reading is treated the same way**, whether it ran out of time or macOS kept a
  folder inside it closed. A coin's data folder, with its blockchain, is the one most likely to be too big to read
  in time, and its wallet may be inside.

What this cannot cover, said plainly. Peel looks for a browser profile at most two levels inside a folder, as it
does for a photo library, so a profile kept deeper in a folder you move yourself is not seen. A wallet kept where no
list here names it, with none of the file names above, cannot be recognized at all. Wallet extensions for Safari
were not studied: Safari's own folders are refused whole, but what such an extension keeps outside them is not
known. Whatever Peel protects, the recovery phrase, written down away from the Mac, is the one copy nothing on the
Mac can take.

## What you can exclude

Anything you add to Exclusions is passed to every scanner, so a file or folder you exclude never appears
in the first place: it is not "shown but skipped". The same case and symlink folding applies, so an
exclusion cannot be side-stepped by spelling the path differently.

It holds in both directions. A folder with something excluded inside it is never moved either, because the
excluded file would go with it: an app's leftover like that is shown, unselected, with the reason, and the
other tools leave it out. An excluded app still appears in Applications, so you can see it, but gets no
removal plan and no reset, in the app and in `peel`. A folder named with its identifier, such as its caches or
its container, is left out of every page and never moved, nor is a folder holding one a level or two down. Its
other files, such as plug-ins, receipts, or a folder named after the app, go by files and folders only, so to
keep them, exclude them too.

If the saved list is there and cannot be read, Peel does not treat it as empty. It moves nothing until you
start over in Settings, `peel` refuses, and the file it could not read is kept beside the new one.

## Resetting an app

A reset clears an app's settings and never the app itself.

- It lists only files that are certainly that app's, and the app has to be quit, both when the reset starts and when
  saved settings are put back.
- Before anything moves, Peel saves the app's settings, and if that copy fails, nothing moves. Settings lists the
  saved copies, where each can be put back or cleared, since one can hold a license key, and they stay until you
  clear them. Putting one back asks first, and saves the settings the app has now as a copy of their own before it
  replaces them.
- What the app keeps for you (its Application Support folder, group containers, and application scripts) goes only
  when you select it, and is never offered for Mail, Messages, Notes, or Photos.
- Inside a sandboxed app's container, a reset touches only the app's preferences, saved state, caches, logs, and web
  data, never `Documents`, `Application Support`, or `Autosave Information`. Web data, which signs you out of
  websites, is offered but never selected for you, and a folder that holds a wallet's keys is never offered, even
  among those: BlueWallet keeps its wallet in its container's caches.

## Terminal's settings

The Terminal page changes Terminal's own preferences and nothing else there: it adds Peel's themes as profiles of
their own, named "Peel" and the theme's name, chooses the profile Terminal opens with, sets Option as Meta and the
bell in the Peel theme in use, and can keep Terminal from reopening its windows.

- Choosing a theme never changes or removes a profile it did not write, or one you changed since. Option as Meta and
  the bell are the one exception, since you ask for them: like Terminal's own settings, they change the Peel theme
  Terminal opens with, whoever wrote it and whatever you changed in it.
- Put Back gives Terminal the profiles it used before and takes away only Peel's own, still as Peel wrote them.
- Peel writes none of this while Terminal is open, since Terminal would not see the change and would write its own
  settings over it. The one exception is the switch that keeps Terminal from reopening its windows: Terminal reads
  that one, `NSQuitAlwaysKeepsWindows`, only when it quits, so Peel sets it at once and it takes effect the next time
  Terminal quits.

Leaving out the "Last login" line makes an empty `~/.hushlogin`, the file `login` looks for, and turning it off again
moves that file to the Trash, recorded in History. Peel never edits your shell's files: to stop the shell from saving
its sessions, it shows the line to add yourself.

The Shell and SSH tabs write only two files of Peel's own, in its folder. zsh and ssh read them only through the line
you add to `~/.zshrc` and the two lines you add at the end of `~/.ssh/config`, and Peel never edits those files. Turn
All Off empties Peel's files, and a line left in yours then does nothing. The Git tab changes Git's settings only with
`git config --global`, Git's own command, after noting what each key held: turning a setting off puts that back, and
a value you changed since is left as it is. A setting you made yourself goes back to Git's default when you turn it
off, and Turn All Off does that to every one, as its question says. The Tools tab installs nothing: it shows the
commands to copy.

## The helper that runs as root

Peel installs a helper for the few things that need administrator rights: moving items in the folders it serves
to the Trash, putting them back, and starting, stopping, enabling, or disabling another vendor's launch daemon; when
Peel is removed, it also moves its own ledger to the Trash. It is deliberately small: no shell, no arbitrary paths,
and it fails closed.

- It answers administrators only, and only a copy of Peel signed by the same team with its Developer ID,
  built so it can't be debugged, no older a build than the helper itself, that speaks the helper's own version.
  All of it is checked when the app connects and again with each request, so an account that stops being an
  administrator is refused from then on, and a message from any other program closes the connection. macOS starts
  the helper only as the developer's own build of it, so other code put in its place never runs as root.
- It refuses the list above on its own, without asking the app, and asks it both ways: a folder that holds
  something on the list is refused like the thing itself.
- It serves a fixed list of folders and refuses everything else: `/Applications`, for apps only; eight folders
  of `/Library` (Application Support, Caches, Preferences, Logs, LaunchAgents, LaunchDaemons,
  PrivilegedHelperTools, and StartupItems) and the 22 that hold plug-ins; the installer receipts in
  `/private/var/db/receipts`; the links in `/usr/local/bin`, `/usr/local/sbin`, and the four folders of
  `/usr/local` that shell completions are linked into; and the Library of the administrator who asks.
- It takes at most 100 items in one request, and quits 30 seconds after its last request ends, or as soon as
  it is idle once an update has replaced it, so it isn't left running.
- A path with a control character in it is refused. The rules read the whole name and the system stops at
  the first zero byte, so such a name would be checked as one thing and moved as another.
- It starts, stops, enables, and disables launch daemons only for other vendors. What macOS ships is
  refused by the label each daemon declares, not by its file name, and if that list cannot be read it
  refuses every daemon rather than allowing them all. It never acts on itself: Peel's helper is installed
  and uninstalled in Settings, and Background Items shows it without controls.
- From the folders command-line tools and their shell completions are linked into, `/usr/local/bin`,
  `/usr/local/sbin`, and the completion folders of `/usr/local` (`share/zsh/site-functions`,
  `share/fish/vendor_completions.d`, `etc/bash_completion.d`, and `share/pwsh/completions`), it takes only a link,
  never a file, and only one that leads nowhere. Peel sends an app's links there after the app itself, so they go
  once the app is gone, and a link that still leads to something stays. The one exception is a link to the `peel`
  command inside the Peel the helper runs from, which Remove Peel hands it before the helper goes.
- It never reuses a path after checking it. It opens the parent directory, checks the item there as the system
  names that directory, works only through that descriptor, and moves the item only while it is still the one it
  checked, so a folder or an item swapped after the check leads nowhere.
- "Put Back" is asked for by a record any process running as you can rewrite, so the helper believes none of
  it. It keeps its own ledger, in a folder that is root's alone, of what it moved and from where: the item is
  recognized by what it is (not by its name or place in the Trash), and it goes back only to the exact place
  the helper took it from. Something dropped into your Trash by hand, or swapped in under a known name, stays
  there. An item moves only once its record is on the drive itself, so a power cut can't keep the move and lose
  the record. While the ledger can't be read, the helper moves nothing and puts nothing back; one it can't make
  sense of is kept under another name, never written over, and a new one begins. A folder that code is loaded from
  takes back only what is still owned by root and writable by nobody else.

If you never install the helper, Peel still works; it just cannot touch what needs administrator rights.
Home lists the helper as required for that reason, and keeps a reminder there until it is installed.
