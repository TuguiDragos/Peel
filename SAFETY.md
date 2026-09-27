# Safety

Peel removes files. So the question that matters most isn't whether someone can break in. It is **whether Peel can
take something you can't get back**, and this page answers it: what Peel never removes, what it never deletes, what
it selects for you and what it leaves to you, how it keeps crypto wallets, how a reset stays within an app's
settings, and what its helper, which runs as root, may do.

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
| `Mail`, `Messages` | Your mail and your messages. |
| `Safari` | Bookmarks, history, reading list. |
| `Calendars`, `Reminders` | Your calendars and reminders, where older systems kept them. |
| `Group Containers/` any of Apple's own | Where macOS 26 keeps notes, reminders, calendars, voice memos, the journal, and more. Apple moves these between releases, so they are recognized by their name (`com.apple.` after an optional team and an optional `group.`, `groups.`, or `systemgroup.`), not from a list. |
| `Shortcuts` and its two group containers, `HomeKit`, `Accounts`, `Finance`, `IdentityServices` | Your shortcuts, your home, your accounts and what they hold. |
| `Application Support/FaceTime`, `CallHistoryTransactions` | Calls. |
| `Containers/com.apple.freeform`, `com.apple.journal`, Stickies' notes, Safari's own store | Boards, journal entries, stickies, and tabs. |
| `.Trash` | Already-deleted things are not Peel's to delete again. |
| `.ssh`, `.gnupg`, `.aws`, `.password-store` | Keys, credentials, secrets. |
| `.android/debug.keystore`, `.m2/settings-security.xml`, `.gradle/gradle.properties`, `.git-credentials` | One key or credential each, named on its own so the cache around it can still be cleaned: the file stays, and so does any folder that holds it. |
| The keys of desktop wallets and key tools: Bitcoin Core's `wallets` and `wallet.dat`, and those of Litecoin, Dogecoin, Dash, and Zcash; Monero's `wallets`; the Electrum family's, Sparrow's, Wasabi's, and Specter's; Exodus's `exodus.wallet` and `Backups`; Atomic, OneKey, Frame, Rabby, Bisq, Liana, Nunchuk, and Green; geth, Foundry, and Hardhat keystores; the Lightning nodes; and the Solana, Sui, Aptos, NEAR, Tezos, Cosmos, Cardano, Decred, Chia, Grin, and Kaspa key files, 58 places in all | Lose one and what it holds is gone unless its seed phrase was kept somewhere else. Each is named on its own, read from the project's own documentation or source, so the key stays, and so does any folder that holds it, while what comes back on its own beside it, such as a downloaded blockchain, can still go. |
| `.config`, `.cache`, `.local`, your shell and git settings (`.zshrc`, `.gitconfig`, `.netrc`, `.npmrc`, and the like), and `.kube/config` | Shared by many tools and owned by no app. They are never removed themselves; what one tool keeps inside `.config`, `.cache`, or `.local` still can be. |

Outside your home: everything inside `/System`, `/usr`, `/bin`, `/sbin`, and `/Library/Updates`, where macOS
stages its own updates. And these folders themselves, though not what is inside them: `/`, `/Applications`,
`/Library`, `/Users`, `/Users/Shared`, `/Volumes`, `/opt`, `/private` and its `var`, `tmp`, and `etc`, `/cores`,
your home folder, and every folder Peel searches, such as `~/Library/Caches`, which is looked inside and never
moved whole. Anything System Integrity Protection guards, which macOS marks as restricted, is refused as well.

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
every account starts with (Desktop, Documents, Downloads, Movies, Music, Pictures, Public) are never moved
themselves, though what you choose inside them can be. Neither are the files of the global preferences domain
(`.GlobalPreferences.plist` and its twins): your language, keyboard, and scrolling settings, which belong to no
app.

One step of a removal is not a move to the Trash: after a preference file has gone, Peel tells macOS to
forget that preference domain (`defaults delete`), or the system could write the file again from memory.
On macOS 26 the system then answers that the domain is not found and changes nothing, and a file put back from
History is read again at once, so History undoes it for an app that has not run since. Even so, it is
only done for a file that went from your own `~/Library/Preferences`, never for the copy every user
shares in `/Library/Preferences`, never while the app's container still holds its own settings, never for one
of Apple's domains on another app's behalf, and never for the global domain under any of its names.

**The check is not a string comparison.** A disk is case-insensitive unless you went out of your way, so
`~/Library/mobile documents` is the same folder as `~/Library/Mobile Documents`; `/var` and `/private/var`
are one folder with two names; and a symbolic link in any parent gives a third. All of those spellings are
folded together before the check, and there are tests that try to get past it by each route.

**And a name is not the thing.** macOS answers to names that appear in no list of spellings: a whole path
can follow `/.nofollow/` or `/.resolve/0/`, and `/.vol/<device>/<inode>` reaches a file by its numbers
alone. The usual way of resolving a path folds none of them, and the Trash takes a file under each. So Peel
asks the system what it calls the item, from an open descriptor rather than from the text, and then asks the
disk what the item *is*. Every place the table names in your home, `/Library/Keychains`, and each folder above
that stays itself are known by their device and inode as well as by name, wherever a link leads them, and an
item is refused when it, or any folder it really sits in, is one of them. That also stops a file name that
begins with a combining accent, which text comparison cannot see the start of. Everything else on this page is
judged by the item's names: as written, where it really sits, and as the system names it, spelled as the disk
stores it.

**And the thing judged is the thing moved.** A check made by name and a move made by name are two looks at
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
That includes an installer receipt you ask Peel to forget: the two files that make it up go to the Trash
through the helper, where `pkgutil --forget` would have discarded them for good. Quitting Peel waits for a
removal until History has it, `peel` carries on through Ctrl-C or a closed terminal until it has written History,
and each item is written down the moment it moves, so one cut short by a crash or Force Quit still reaches
History, as an interrupted removal, the next time Peel or `peel` opens it. The space is freed when *you* empty
the Trash: Peel never does that for you.

Right before anything moves, Peel looks at the files other programs of yours hold open, and leaves where it is any
file or folder with one of them inside, naming the program: moving a database or a cache from under an agent, a
daemon, or a server that is using it would break it. Programs that run as another account or as root, macOS's own
among them, cannot be seen this way, which is why Space also leaves macOS's own caches unselected.

A move to the Trash, or back from it, never replaces what is already at the new name. Most disks refuse that by
themselves; on one that cannot, such as exFAT, Peel first takes the name with an empty placeholder, which only a
free name allows, and the move then replaces the placeholder.

What Peel deletes outright is only its own: its list of refusals, when `peel history --refused --clear` is asked to
forget it, and such a placeholder, when the move it was made for fails.

Three things Peel starts can't be undone by History, and Peel says so before you confirm each of them: Homebrew's own
uninstall and Clean Up, which delete what they remove, and resetting an app's privacy permissions, which is off until
you choose it. An upgrade from the Homebrew page never cleans up on its own, although Homebrew would by default. If one
of Homebrew's own settings files (`brew.env`) turns that cleanup back on, the Homebrew page says so and Peel leaves
upgrades to Terminal. Forgetting a preference domain (described above) is not one of the three: it is done only once the
file is in the Trash, and putting the file back undoes it, until the app writes its settings again.

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

## What is selected for you

Only matches Peel is `certain` or `likely` about, and only when nothing else installed on the Mac uses them.
Anything shared with another app is shown and left unselected, and so is what another copy of the app uses: one
macOS knows anywhere, such as an older copy in Downloads or one on another disk, is named by where it is. An app of
the same maker kept outside the Applications folders, such as a Nightly build on another disk, counts like one
inside them. Something matched by the app's name alone inside another app's folder, or one of Apple's, is shown and
never selected, since it is most likely that app's data about this one; so is something matched by name alone at the
top of your home folder or of a Library, where a name is only a guess. A plug-in's name says what it does rather than
who made it, so a plug-in called like the app is selected only when the identifier it declares is the app's or its
maker's: another maker's plug-in with the app's name is never selected. And nothing at all is selected for an app
that would stay: one macOS keeps, one the helper may not move, or one that needs the helper while it cannot act.
When you remove several apps at once and deselect one of them, it stays too: its files leave the selection, those it
shares with the other apps included, and selecting it again brings them back.

Peel itself is listed on its own page with what it keeps, and nothing of it can be selected there or among other
apps. It is removed only by Remove Peel, in Settings, which takes its helper and login item away first.

Never selected for you, even when found: Xcode's archives of the apps you built and the symbols it copied from your
devices, both needed to read crash reports, model weights, the packages a tool keeps installed outside your projects,
virtual environments, the installers and boxes a tool keeps for you to install again, a cache macOS keeps for its own
services in `~/Library/Caches` (Spotlight's, iCloud's, the fonts') or in the container of one of Apple's apps,
`/Users/Shared` (it belongs to every account, not just yours), a project you worked on this week, a folder with a
repository, a wallet, or a signing key inside, a folder macOS would not let Peel read, and a folder Peel could not
measure in time. Those last two are shown with their size as "Unknown", never as zero, in every tool and in History
once they are moved: a folder too big to read quickly may be exactly the one with work inside, and nothing is
selected for you without saying how much it is. A total that leaves such a folder out reads "Over" what is known.

A repository inside a folder its tool tags as a cache (`CACHEDIR.TAG`) is the one exception: the tool says it makes
everything in there again. Swift Package Manager tags `.build`, where it clones a package's dependencies, and
`swift package reset` deletes that folder whole, so Build Artifacts can still select it. Carthage's checkouts, which
people commit in, carry no such tag and are never selected.

Build Artifacts selects what a build or a package manager makes again from the project's own files, such as
`DerivedData`, `.build`, and `.next`, once Peel can tell that nothing in the project has changed for a week. That
includes `node_modules` and `Pods`, which `npm install` and `pod install` put back from the project's `package.json` and
`Podfile`. A Python environment (`.venv`, `venv`) is listed and never selected, since packages are often installed into
one by hand, and so is Terraform's `.terraform`, which keeps the workspace you chose. A folder whose name says nothing
on its own, such as `target` or `build`, is listed and never selected either.

Orphaned Files selects nothing for you, and its Select All and `peel orphans --remove` leave these folders out as
well: one in `/Users/Shared`, one with a repository, a wallet, or a signing key inside, or one Peel could not read
or measure in time, moves only when you select it yourself.

In Duplicates, one copy of every group always stays, and a file that changed since the scan is refused. Nothing
inside an app or another package is ever offered, nor a hidden folder, such as a tool's settings in `~/.config`:
they only count toward the folder around them.

What you select on the pages that free space (Orphaned Files, Space, Developer, Build Artifacts, Installers and
Backups, Duplicates, and File Search) stays selected while you look at the others, and Move to Trash on any of
them moves all of it. Only a page you have opened counts: Developer and Build Artifacts select for you in every
tool and project they list, and what they selected on a page you never saw stays where it is. Before anything
moves, the question lists every page with how much it holds, and each page's part is moved by its own tool, with
that tool's checks at that moment: Developer waits for its app to quit, Space leaves out what an app opened since
is writing to, and Duplicates refuses a copy that changed.

Some things are shown and never removed at all, because the removal cannot be undone: local Time Machine
snapshots are explained, never deleted.

## Crypto wallets

A wallet's keys can be the only way to what they hold, so Peel keeps them in four ways.

- **Where wallets keep their keys is never removed.** The 58 places in the table at the top of this page, each
  read from the wallet's own documentation or source, are refused outright by the app, the `peel` tool, and the
  helper, and so is any folder that holds one. When a wallet's folder was moved to another disk and linked back,
  as is common once a blockchain outgrows the startup disk, its keys are refused there as well. What comes back on
  its own beside a key, such as a downloaded blockchain, can still go.
- **A browser profile with a wallet stays.** A wallet extension such as MetaMask or Phantom keeps its vault in the
  browser's profile, beside `Local Storage`, which every extension shares. So a profile that holds one of the
  wallet extensions Peel knows (those of more than 60 wallets, for Chrome, Brave, Edge, Arc, Opera, Vivaldi, and
  Firefox) or Brave's own wallet stays, and so does a folder that holds it a level or two down, which is where a
  browser keeps its profiles (`Google/Chrome/Default`): uninstalling a browser never takes its wallet. The rest of
  what a browser keeps, such as its caches, can still go.
- **A wallet found anywhere else is never selected for you.** When an uninstall or Orphaned Files measures a
  folder, it also looks inside for the names wallets and key tools give their files: anything called
  `wallet.dat`, `wallets`, `keystore`, `seed.dat`, `hsm_secret`, or `channel.backup`, anything ending in `.wallet`
  or `.keys`, and the others `FileSize.isWallet` lists. A folder with one inside is shown with that reason and
  never selected for you, not even by Select All in Orphaned Files, `peel uninstall`, or `peel orphans --remove`.
  You can still select it yourself, because a name can mislead: a Java project keeps a `keystore` too.
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

Anything you add to Exclusions is passed to every scanner, so it never appears in the first place: it is
not "shown but skipped". The same case and symlink folding applies, so an exclusion cannot be side-stepped
by spelling the path differently.

It holds in both directions. A folder with something excluded inside it is never moved either, because the
excluded file would go with it: an app's leftover like that is shown, unselected, with the reason, and the
other tools leave it out. An excluded app gets no removal plan and no reset, in the app and in `peel`.

If the saved list is there and cannot be read, Peel does not treat it as empty. It moves nothing until you
start over in Settings, `peel` refuses, and the file it could not read is kept beside the new one.

## Resetting an app

A reset clears an app's settings and never the app itself. It lists only files that are certainly that app's, and the
app has to be quit, both when the reset starts and when saved settings are put back. Before anything moves, Peel saves
the app's settings, and if that copy fails, nothing moves; Settings lists the saved copies, where each can be put back
or cleared, since one can hold a license key, and they stay until you clear them. Putting one back asks first, and saves
the settings the app has now as a copy of their own before it replaces them. What the app keeps for you (its Application
Support folder, group containers, and application scripts) goes only when you select it, and is never offered for Mail,
Messages, Notes, or Photos. Inside a sandboxed app's container, a reset touches only the app's preferences, saved state,
caches, logs, and web data, never `Documents`, `Application Support`, or `Autosave Information`; web data, which signs
you out of websites, is offered but never selected for you. A folder that holds a wallet's keys is never offered, even
among those: BlueWallet keeps its wallet in its container's caches.

## The helper that runs as root

Peel installs a helper for the few things that need administrator rights: moving items in the folders it serves
to the Trash, putting them back, and starting, stopping, enabling, or disabling another vendor's launch daemon. It
is deliberately small: no shell, no arbitrary paths, and it fails closed.

- It answers administrators only, and only a copy of Peel signed by the same team. Both are checked when the
  app connects and again with each request, so an account that stops being an administrator is refused from
  then on, and a message from any other program closes the connection.
- It refuses the list above on its own, without asking the app, and asks it both ways: a folder that holds
  something on the list is refused like the thing itself.
- A path with a control character in it is refused. The rules read the whole name and the system stops at
  the first zero byte, so such a name would be checked as one thing and moved as another.
- It starts, stops, enables, and disables launch daemons only for other vendors. What macOS ships is
  refused by the label each daemon declares, not by its file name, and if that list cannot be read it
  refuses every daemon rather than allowing them all. It never acts on itself: Peel's helper is installed
  and uninstalled in Settings, and Background Items shows it without controls.
- From the folders command-line tools are linked into, `/usr/local/bin` and `/usr/local/sbin`, it takes only
  a link, never a file, and only one that leads nowhere. Peel sends an app's links there after the app itself,
  so they go once the app is gone, and a link that still leads to something stays.
- It never reuses a path after checking it. It holds the parent directory open and works through that
  descriptor, so a folder swapped after the check leads nowhere.
- "Put Back" is asked for by a record any process running as you can rewrite, so the helper believes none of
  it. It keeps its own ledger, in a folder that is root's alone, of what it moved and from where: the item is
  recognized by what it is (not by its name or place in the Trash), and it goes back only to the exact place
  the helper took it from. Something dropped into your Trash by hand, or swapped in under a known name, stays
  there. While the ledger can't be read, the helper moves nothing and puts nothing back; one it can't make sense
  of is kept under another name, never written over, and a new one begins. A folder that code is loaded from
  takes back only what is still owned by root and writable by nobody else.

If you never install the helper, Peel still works; it just cannot touch what needs administrator rights.
Home lists the helper as required for that reason, and keeps a reminder there until it is installed.
