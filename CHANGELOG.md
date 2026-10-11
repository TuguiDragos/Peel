# Changelog

Every release of Peel is listed here, newest first. The version is the one About Peel shows, and each entry groups
its changes the way [Keep a Changelog](https://keepachangelog.com/) suggests.

## 1.1.0 (not released yet)

> [!IMPORTANT]
> Peel 1.0.1 can't install an update itself. To update from it, quit Peel, move it from Applications to the Trash,
> and drag the new Peel into Applications: your History, exclusions, and settings stay. If Homebrew installed it, run
> `brew upgrade --cask peel` instead. If Home then says the helper isn't answering, choose Repair. From 1.1.0 on,
> Peel updates itself when you choose Install Update.

### Added

- Peel tells you when a new version is out and updates itself when you choose to.
- Every page that moves files shows how far it has got, and which app it is waiting for to quit.
- Finds more to clean, such as downloads Safari never finished and updates Google's updater keeps.
- Lists and uninstalls the few apps that carry no identifier, which it couldn't see before.

### Changed

- Never selects for you what may exist only on your Mac, such as WhatsApp's chats, game saves, and app backups.
- Leaves an app with a system extension to Finder, and security and management tools to their makers' uninstallers.
- Says what its helper is doing, and within seconds when the helper doesn't answer, with a way to repair it.
- Leaves alone more of what macOS and other apps rely on, such as the folder crash reports are saved in and a Godot
  project's export passwords.

### Fixed

- Many smaller fixes: Peel never moves the folder it runs from, and never asks to quit what you can't quit.
- No longer points to an app's leftovers when another copy of the app is still installed.

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
