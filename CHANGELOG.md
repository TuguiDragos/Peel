# Changelog

Every release of Peel is listed here, newest first. The version is the one About Peel shows, and each entry groups
its changes the way [Keep a Changelog](https://keepachangelog.com/) suggests.

## 1.0.1

The first public release, for macOS 26 and later, on Apple silicon and Intel Macs.

### Added

- Uninstalls apps together with the files they leave behind, and shows for each file why it matched and how
  sure Peel is.
- Finds files left by apps that are gone, caches of developer tools, what builds left in your projects,
  duplicate files and folders, installers and backups, files already safe in iCloud, large and old files, and
  what is taking up space.
- Resets an app's settings without uninstalling it, after saving them so they can be put back.
- Lists background items, extensions, plug-ins, installer receipts, Homebrew packages, and software that still
  needs Rosetta.
- Changes settings macOS has but doesn't show, and puts back what was there when you turn one off.
- Gives Terminal one of 29 dark themes built on Apple's Clear Dark, and puts back the profile it used before.
- Sets up the command line from the same page: choose a prompt, turn on settings that zsh, Git, and ssh already
  have, and copy the Homebrew commands for command-line tools worth having, with the lines each one needs.
- Moves what it removes to the Trash instead of deleting it, and keeps a History that puts it back and lists
  what it didn't move, with the reason.
- Keeps what you select on the pages that free space while you look at the others, and moves it all at once, as
  one entry in History.
- Leaves alone the files, folders, and apps you exclude.
- Checks your apps for updates, and watches the Trash for apps you remove yourself.
- Says in About when a new version of Peel is out, with where to get it, and downloads nothing itself.
- Exports what is installed and where each app came from, as JSON, CSV, plain text, or a Brewfile.
- Comes with the `peel` command for Terminal, a Finder extension, and actions for Shortcuts.
- Speaks English and 17 other languages.
