import ArgumentParser
import Darwin
import Foundation
import PeelCore
import Synchronization
// `wcwidth_l`, which Swift imports when both are imported, as the SDK's module map says.
import wchar_h
import xlocale

struct CommandFailure: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}

enum Output {
    /// The locale for every size and number the tool prints. The tool speaks English only, and a script reading
    /// its output must get the same format whatever region the Mac is set to.
    static let locale = Locale(identifier: "en_US_POSIX")

    /// What a command printed, kept in place of standard output and standard error while a test runs it inside
    /// `Output.$collected.withValue`, so the test can read what a person or a script would have read.
    final class Collected: Sendable {
        private let printed = Mutex((output: "", notes: "", writes: 0))

        var output: String { printed.withLock { $0.output } }
        var notes: String { printed.withLock { $0.notes } }
        /// How many times standard output was written to.
        var writes: Int { printed.withLock { $0.writes } }

        fileprivate func add(output text: String) {
            printed.withLock {
                $0.output += text
                $0.writes += 1
            }
        }
        fileprivate func add(note text: String) { printed.withLock { $0.notes += text } }
    }

    @TaskLocal static var collected: Collected?

    static func line(_ text: String = "") {
        write(plain(text) + "\n")
    }

    /// Replaces every character that could hide or reorder text with `?` (`PlainText`), for names and paths from
    /// other people's bundles.
    static func plain(_ text: String) -> String {
        PlainText.of(text)
    }

    /// Returns `name` so the reader can paste it into a command: in single quotes unless every character is a
    /// letter, a digit, or one of `._/+-@%:=,`, which no shell reads as anything but itself, and the first is not
    /// `=`, which zsh reads as a command's path.
    static func quoted(_ name: String) -> String {
        let name = plain(name)
        let isPlain = !name.isEmpty && name.allSatisfy { $0.isLetter || $0.isNumber || "._/+-@%:=,".contains($0) }
            && name.first != "="
        return isPlain ? name : "'\(name.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    /// Writes `text` to standard output unchanged, for output that already ends in a newline. When the write fails
    /// (a full disk, a closed stdout), the tool exits with status 1. `FileHandle.write(_:)` would instead raise an
    /// exception Swift can't catch, and the tool would crash. A pipe whose reader has gone ends the process with
    /// SIGPIPE before the write returns (`man 2 write`), except while a removal ignores the signal (`Uninterrupted`).
    static func write(_ text: String) {
        if let collected {
            collected.add(output: text)
            return
        }
        do {
            try FileHandle.standardOutput.write(contentsOf: Data(text.utf8))
        } catch {
            exit(EXIT_FAILURE)
        }
    }

    /// Writes `text` to standard error, which is for the person reading, not for a script. Newlines are kept, and
    /// every other character `plain` hides is replaced with `?`.
    static func note(_ text: String) {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map { plain(String($0)) }
        let written = lines.joined(separator: "\n") + "\n"
        if let collected {
            collected.add(note: written)
            return
        }
        try? FileHandle.standardError.write(contentsOf: Data(written.utf8))
    }

    static func json(_ value: some Encodable) throws {
        write(try jsonText(value))
    }

    static func jsonText(_ value: some Encodable) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return String(decoding: try encoder.encode(value), as: UTF8.self) + "\n"
    }

    /// Prints rows as a table, padding every column but the last to the width of its widest cell, in one write.
    static func table(_ rows: [[String]], indent: String = "") {
        write(paddedCells(rows).map { indent + $0 + "\n" }.joined())
    }

    /// The rows of `table`, one line each, padded in terminal cells.
    static func paddedCells(_ rows: [[String]]) -> [String] {
        let rows = rows.map { $0.map(plain) }
        let locale = newlocale(LC_CTYPE_MASK, "UTF-8", nil)
        defer { if let locale { freelocale(locale) } }
        let widths = rows.map { $0.map { cells($0, in: locale) } }
        let columns = rows.map(\.count).max() ?? 0
        let columnWidths = (0..<columns).map { column in widths.map { column < $0.count ? $0[column] : 0 }.max() ?? 0 }
        return zip(rows, widths).map { row, width in
            row.enumerated().map { index, cell in
                index == row.count - 1 ? cell : cell + String(repeating: " ", count: columnWidths[index] - width[index])
            }
            .joined(separator: "  ")
        }
    }

    /// The terminal cells `text` takes: two for an emoji or a wide East Asian character, none for a combining mark.
    static func cells(_ text: String, in locale: locale_t?) -> Int {
        text.reduce(0) { total, character in
            let scalars = character.unicodeScalars
            // A flag, and a character followed by U+FE0F, which asks for its emoji form, are drawn as an emoji.
            if scalars.contains(where: { $0.properties.isEmojiPresentation || $0.value == 0xFE0F }) { return total + 2 }
            let width = scalars.map { Int(wcwidth_l(wchar_t(bitPattern: $0.value), locale)) }.max() ?? 0
            // -1 is a character `wcwidth_l` can't print, which a terminal draws as a box.
            return total + (width < 0 ? 1 : width)
        }
    }

    /// Formats `bytes` as a file size. `spellsOutZero` is turned off, since by default zero is spelled out as a word.
    static func size(_ bytes: Int64) -> String {
        bytes.formatted(.byteCount(style: .file, spellsOutZero: false).locale(locale))
    }

    /// Formats a size that may not be known: nil becomes "unknown", never zero.
    static func size(_ bytes: Int64?) -> String {
        bytes.map(size) ?? "unknown"
    }

    static func size(_ total: SizeTotal) -> String {
        if total.isComplete { return size(total.known) }
        return total.known > 0 ? "over " + size(total.known) : "unknown"
    }

    /// The full path with no trailing slash, the same form `peel inventory` and every record use.
    static func path(_ url: URL) -> String {
        let path = PathPattern.comparablePath(of: url)
        // Foundation leaves `/private` out of these links of macOS's only for a path that exists.
        let isUnderALink = ["/private/var/", "/private/tmp/", "/private/etc/"].contains {
            path.utf8.starts(with: $0.utf8)
        }
        return isUnderALink ? String(path.dropFirst("/private".count)) : path
    }

    /// Names joined as an English list: "A", "A and B", "A, B, and C".
    static func list(_ names: [String]) -> String {
        switch names.count {
        case 0: ""
        case 1: names[0]
        case 2: "\(names[0]) and \(names[1])"
        default: names.dropLast().joined(separator: ", ") + ", and " + names[names.count - 1]
        }
    }

    static func number(_ value: Int) -> String {
        value.formatted(.number.locale(locale))
    }

    /// Formats `date` as an ISO 8601 day in the Mac's time zone, as `peel inventory` does, so it matches the day
    /// the Finder shows. Tests pass a zone so they don't depend on where they run.
    static func day(_ date: Date, timeZone: TimeZone = .current) -> String {
        Inventory.day(date, timeZone: timeZone)
    }

    static func count(_ value: Int, _ singular: String, _ plural: String) -> String {
        "\(number(value)) \(value == 1 ? singular : plural)"
    }

    static let fullDiskAccessAdvice = "Give your terminal app Full Disk Access in System Settings to read the folders macOS protects."

    /// What a scan couldn't look into: the folders, why when their permissions are why, and then Full Disk Access
    /// when it would open one of them.
    static func unreadableNote(for folders: [URL], needsFullDiskAccess: Bool) -> String {
        let note = "Peel couldn't look inside \(list(named(folders))), so something may be there that isn't listed."
        return [note, whyNotRead(folders), needsFullDiskAccess ? fullDiskAccessAdvice : nil]
            .compactMap(\.self).joined(separator: " ")
    }

    /// The sentence that says the permissions kept Peel out of `items`, or nil when they didn't.
    static func whyNotRead(_ items: [URL]) -> String? {
        let closed = items.count(where: FileAccess.isClosedByItsPermissions)
        if closed == 0 { return nil }
        if closed < items.count { return "The permissions of some of them don't let your account read them." }
        return closed == 1
            ? "Its permissions don't let your account read it."
            : "Their permissions don't let your account read them."
    }

    private static let mostNamedFolders = 4

    /// The folders to name in a list: the first four, and then how many more, as the Peel app names them.
    static func named(_ folders: [URL]) -> [String] {
        let paths = folders.map { plain(path($0)) }
        guard paths.count > mostNamedFolders else { return paths }
        let more = count(paths.count - mostNamedFolders, "more folder", "more folders")
        return Array(paths.prefix(mostNamedFolders)) + [more]
    }

    /// What a reading of the apps could not read, so the apps in it are missing from what is written, or nil when it
    /// read everything.
    static func unreadableNote(for catalog: AppScan) -> String? {
        var notes: [String] = []
        if catalog.listOfFoldersUnreadable {
            notes.append("Peel can't read its list of app folders, so the apps in them aren't listed. Start it over in Settings > General > App Folders." + catalog.whyListOfFoldersUnreadable.sentence)
        }
        if !catalog.unreadable.isEmpty {
            notes.append(unreadableNote(for: catalog.unreadable, needsFullDiskAccess: catalog.needsFullDiskAccess))
        }
        if !catalog.foldersLeftOut.isEmpty {
            let folders = list(named(catalog.foldersLeftOut.map(\.folder)))
            notes.append("Peel no longer looks in \(folders), so the apps there aren't listed. Choose the folder that holds the apps in Settings > General > App Folders.")
        }
        return notes.isEmpty ? nil : notes.joined(separator: "\n")
    }

    /// Whether the user can answer a question about the plan printed above it: standard input, standard output and
    /// standard error must all be a terminal. The plan goes to standard output and the question to standard error,
    /// so with either redirected the user would answer without seeing it.
    static var canAsk: Bool { isatty(STDIN_FILENO) == 1 && isatty(STDOUT_FILENO) == 1 && isatty(STDERR_FILENO) == 1 }

    /// Throws when the user can't be asked. Commands call this from `validate()`, where ArgumentParser knows which
    /// subcommand was typed and so prints that subcommand's usage.
    static func requireConfirmable() throws {
        guard canAsk else { throw ValidationError("Add --yes to confirm when Peel can't ask.") }
    }

    /// Exit code 2, for when the user answers no. `CleanExit` would report success, and
    /// `peel uninstall Foo && next-step` would then run `next-step` anyway.
    static let declined = ExitCode(2)

    /// Asks `question` on standard error, and throws `declined` unless the user answers y or yes. What was typed
    /// before the question appeared is dropped first, so a key pressed during a long scan never answers it.
    static func confirm(_ question: String) throws {
        try requireConfirmable()
        tcflush(STDIN_FILENO, TCIFLUSH)
        try? FileHandle.standardError.write(contentsOf: Data(plain("\(question) [y/N] ").utf8))
        let answer = readLine()?.trimmingCharacters(in: .whitespaces).lowercased()
        guard answer == "y" || answer == "yes" else {
            note("Nothing was moved.")
            throw declined
        }
    }
}

extension RestoreFailure {
    var summary: String {
        switch self {
        case .missingFromTrash: "it isn't in the Trash anymore"
        case .alreadyThere: "something is there already"
        case .needsHelper: "it needs administrator access, so put it back with the Peel app"
        case .notAllowed(.excluded):
            "your exclusions keep Peel from putting anything there; take it off the list, or drag it out of the Trash in Finder"
        case .notAllowed(let refusal): "Peel protects that place now (\(refusal.summary)); drag it out of the Trash in Finder"
        case .notInATrash: "it isn't in the Trash where Peel put it"
        case .notAllowedByTheHelper(let message): Output.plain(message)
        case .locked: "it is locked; unlock it in Finder's Get Info"
        case .folderLocked: "the folder it goes back to is locked; unlock it in Finder's Get Info"
        case .folderGone:
            "the folder it goes back to isn't there anymore; put that folder back first, or drag it out of the Trash in Finder"
        case .needsAppManagement:
            "macOS lets your terminal app put back another developer's app only with App Management; allow it in System Settings > Privacy & Security > App Management, or put it back with the Peel app"
        case .notPermitted: "macOS didn't allow it"
        case .failed(let message): Output.plain(message)
        case .replacementStays(let reason):
            "the version now in its place couldn't move to the Trash first (\(reason.summary))"
        }
    }
}

extension RemovalLogProblem {
    var summary: String {
        switch self {
        case .damaged(let setAside): "History was damaged, so it was kept as \(Output.plain(Output.path(setAside))) and started again."
        case .unreadable(let why):
            "History couldn't be read, so Peel moves nothing until you start it over in the Peel app's History." + why.sentence
        case .couldNotRecord(let why): "History couldn't be saved, so the last removal isn't in it." + why.sentence
        case .couldNotUpdate(let why): "History couldn't be saved, so what was put back is still listed in it." + why.sentence
        case .journalSetAside(let setAside):
            "Peel couldn't read its record of a removal under way, so it kept it as \(Output.plain(Output.path(setAside)))."
                + " If a removal was cut short, what it moved is in the Trash but isn't listed in History."
        }
    }
}

extension FileProblem {
    /// Why, as a sentence of its own after the one it explains.
    var sentence: String {
        switch self {
        case .notAFile: " Something other than a file, such as a folder, is where the file should be."
        case .tooLarge: " The file is larger than Peel ever writes it, so Peel doesn't read it."
        case .damaged: " The file's contents aren't in a form Peel can read."
        case .failed(let error): " macOS answered: \(Output.plain(error.localizedDescription))"
        }
    }
}

extension FileProblem? {
    /// Why, or nothing when it isn't known.
    var sentence: String {
        self?.sentence ?? ""
    }
}

extension RefusalLogProblem {
    var summary: String {
        switch self {
        case .damaged(let setAside):
            "The list of refusals was damaged, so it was kept as \(Output.plain(Output.path(setAside)))"
                + " and started again."
        case .unreadable(let why):
            "The list of refusals couldn't be read, so Peel writes nothing to it until you clear it with"
                + " `peel history --refused --clear` or start it over in the Peel app's History." + why.sentence
        case .couldNotRecord(let why):
            "The list of refusals couldn't be saved, so what stayed this time isn't in it." + why.sentence
        }
    }
}

extension MatchReason {
    var summary: String {
        switch self {
        case .bundleIdentifier: "bundle identifier"
        case .embeddedBundleIdentifier: "helper or extension"
        case .applicationGroup: "app group"
        case .bundleIdentifierPrefix: "identifier prefix"
        case .name: "app name"
        case .teamIdentifier: "developer team"
        case .vendorPrefix: "developer"
        case .namePrefix: "name prefix"
        case .launchdJob: "runs the app"
        case .linksToTheApp: "leads into the app"
        case .leadsToTheApp: "leads to the app"
        case .nativeMessagingHost: "lets a browser extension run the app"
        case .installerReceipt: "installer receipt"
        case .homebrewReceipt: "Homebrew receipt"
        case .leadsIntoItsHomebrewReceipt: "leads into the Homebrew receipt"
        case .homebrewCask: "Homebrew cask"
        case .managedByTheApp: "managed by the app"
        case .updaterDownloads: "where its updater keeps its downloads"
        case .namedByTheApp: "named by the app's own files"
        case .documentedByItsMaker: "documented by its maker"
        case .inItsMakersFolder: "in its maker's folder, the maker's last app"
        }
    }
}

extension MatchConfidence {
    /// Spelled out case by case rather than with `String(describing:)`, so the words scripts read don't change
    /// when a case is renamed or the enum gets a description.
    var summary: String {
        switch self {
        case .possible: "possible"
        case .likely: "likely"
        case .certain: "certain"
        }
    }
}

extension GuardRefusal {
    /// Why Peel never moves the item, in the command line's plain English.
    var summary: String {
        switch self {
        case .exclusionsNotKnown: "your exclusions couldn't be read"
        case .excluded: "excluded"
        case .staysItself: "a folder that stays in place, though what is inside may go"
        case .protectedLocation: "part of macOS, or inside something Peel protects"
        case .holdsProtectedData: "holds something Peel protects, such as a keychain or a wallet"
        case .inTheCloud(.cloud): "syncs to your other devices through iCloud or another app, so moving it would remove it from them too"
        case .inTheCloud(.app(let app, let marker)):
            "in a folder \(app.name) syncs to your other devices (its marker is \(Output.plain(Output.path(marker)))), so moving it would remove it from them too"
        case .holdsDocuments: "holds an app's documents"
        case .holdsALibrary: "holds a photo, music, or video library"
        case .holdsWorkKeptInACache: "holds work an app keeps nowhere else, such as an editor's local history"
        case .couldNotLookInside: "macOS wouldn't let Peel look inside to make sure nothing Peel protects is there"
        }
    }
}

extension SyncKeeper {
    /// A note naming the app that syncs some of the items counted, and its marker, or nil for iCloud.
    var note: String? {
        guard case .app(let app, let marker) = self else { return nil }
        return "\(app.name) syncs some of them to your other devices (its marker is \(Output.plain(Output.path(marker))))."
    }

    var record: SyncRecord? {
        guard case .app(let app, let marker) = self else { return nil }
        return SyncRecord(app: app.name, marker: Output.path(marker))
    }
}

/// The app that syncs an item, and the marker it keeps at the root of the folder it syncs.
struct SyncRecord: Encodable, Equatable {
    let app: String
    let marker: String
}

extension HoldBack {
    /// The summary, naming the app that keeps the item in step and its marker when one does.
    func summary(keptInStepBy keeper: SyncKeeper?) -> String {
        guard self == .inTheCloud, case .app(let app, let marker)? = keeper else { return summary }
        return "in a folder \(app.name) syncs to your other devices (its marker is \(Output.plain(Output.path(marker)))), so moving it would remove it from them too"
    }

    /// Why the item was held back, the same reason the app's rows give, in the command line's plain English.
    var summary: String {
        switch self {
        case .holdsRepository: "holds a repository"
        case .trackedByGit: "Git tracks files in it"
        case .gitTrackingNotKnown: "in a Git repository whose tracked files couldn't be read"
        case .gitTrackingNotReadInTime: "reading which files Git tracks here took too long"
        case .keepsItsSetup: "keeps the options its build was set up with"
        case .sharedWithEveryone: "belongs to everyone on this Mac"
        case .listedByAnotherPackage: "another installed package lists it too"
        case .holdsWhatOthersPut: "holds files something besides this package put there"
        case .namedLikeTheApp: "claimed on the app's name alone"
        case .holdsAnExclusion: "holds something you excluded"
        case .notMeasured: "not measured in time"
        case .couldNotBeRead: "macOS wouldn't let Peel read inside"
        case .closedByPermissions: "its permissions keep Peel out"
        case .couldNotLookInside: "macOS wouldn't let Peel look inside to make sure nothing Peel protects is there"
        case .holdsDocuments: "holds the app's documents"
        case .holdsALibrary: "holds a photo, music, or video library"
        case .holdsAWallet: "holds a wallet or a signing key"
        case .holdsAPasswordDatabase: "holds a password database or its key file"
        case .holdsLocalMail: "may hold mail kept only on this Mac"
        case .holdsMessageHistory: "holds message history that may exist only on this Mac"
        case .holdsPasswordsOrCodes: "holds passwords or sign-in codes that may exist only on this Mac"
        case .holdsVPNConnections: "holds VPN connections that may exist only on this Mac"
        case .holdsSignIns: "holds a sign-in to a service, such as a token a tool saved when you logged in"
        case .holdsTorrents: "holds your list of torrents and how far each one got, which may exist only on this Mac"
        case .packageLeftMore: "its package also left items outside the app, which Package Receipts lists only while it stays"
        case .holdsWorkMadeWithTheApp:
            "holds what you made with the app, such as saved games, databases, or its backups, that may exist only here"
        case .holdsSimulators: "holds the app's simulators, with the apps installed in them and their data"
        case .holdsVirtualMachines:
            "holds virtual machines or Windows bottles, with the systems, apps, and files in them"
        case .holdsKeys: "holds a wallet or a key Peel protects"
        case .holdsWorkKeptInACache: "holds work an app keeps nowhere else, such as an editor's local history"
        case .insideAnotherAppsFolder: "inside a folder that belongs to macOS or to another installed app"
        case .holdsAnotherAppsData: "holds what another installed app keeps as its own"
        case .beyondTheHelper: "needs an administrator, and Peel's helper can't move it"
        case .leftToItsUninstaller: "removed by the app's own uninstaller once the app is in the Trash"
        case .neededWhenTheAppLeaves: "needed by a program that runs once the app is in the Trash"
        case .systemExtension:
            "a system extension macOS installed; moving its app to the Trash in Finder asks macOS to remove it"
        case .systemExtensionGoingAtRestart: "a system extension macOS removes at the next restart"
        case .deletableSystemExtension:
            "a network extension macOS installed; System Settings deletes it: in General > Login Items & Extensions, choose By Category, click the Info button beside Network Extensions, then click the More button beside it and choose Delete Extension"
        case .signInPlugIn: "a plug-in macOS may load at login, left to its maker's uninstaller"
        case .loadedByOtherApps: "other apps can load it on their own, such as music apps"
        case .keptByMacOS: "macOS keeps it for its own services"
        case .openedFromMail: "an attachment opened from Mail, which may be the only copy"
        case .crashReport: "a crash report, which the app's developer may still ask for"
        case .inTheCloud: "syncs to your other devices through iCloud or another app, so moving it would remove it from them too"
        case .keepsWhatTheOthersLack: "has Finder tags, a comment, or a resource fork the other copies don't"
        case .keptDownloaded: "Keep Downloaded is on for it in Finder, so iCloud downloads it again"
        case .inAnAppsICloudFolder: "in an app's own iCloud folder, which the app may expect to find on this Mac"
        case .opensOnlyOnline: "holds passwords or a wallet's keys, which would open again only online"
        case .inARepository: "in a repository, so it may be part of a project's work"
        case .openInAProgram: "open in a program right now, which may still be using it"
        case .attachedDiskImage: "a disk image open right now; eject it first"
        case .changedRecently: "changed in the last day, so it may still be downloading"
        case .arrivedRecently: "arrived or changed in the last hour, so it may be in use"
        case .mayStillBeResumed: "a program that resumes downloads, such as a torrent client, may still finish it"
        case .writtenRecently: "written to in the last 15 minutes, so a program may still be using it"
        case .serverStillListens: "a server still listens on the port it is named for and keeps its uploads here"
        case .keptByAnApp: "in a folder an app keeps, and the app may still need it"
        case .appIsRunning: "its app is running and may install this update when it quits"
        case .mayBeTheOnlyCopy: "no installed app's installer and no sign of where it was downloaded from"
        case .encryptedImage: "an encrypted disk image, which holds what you put in it"
        }
    }
}

extension DuplicateFinder.Refusal {
    var summary: String {
        switch self {
        case .protected: "Peel protects what is there, and never moves it"
        case .library: "it is your Library, or a folder in it, where apps keep their data"
        case .mediaFolder(.music): "it is the folder where the Music app keeps its media, or a folder in it"
        case .mediaFolder(.tv): "it is the folder where the TV app keeps its media, or a folder in it"
        case .readOnlyDisk: "it is on a disk that can only be read, so nothing there could move to the Trash"
        case .inAPackage: "it is an app or another package, or inside one, and what is inside belongs to it"
        case .outsideTheHome: "it is outside your home folder, /Users/Shared, and the disks in /Volumes"
        case .insideARepository: "it is a repository, or sits inside one, and Peel leaves repositories alone"
        case .unreachable(let problem): problem.summary
        }
    }
}

extension FolderReach {
    var summary: String {
        switch self {
        case .diskNotConnected(let disk): "it is on \(Output.plain(disk)), a disk that isn't connected now"
        case .gone: "it isn't there anymore"
        case .notAFolder: "it isn't a folder"
        case .closed: "its permissions, or those of a folder on its way, keep your account out"
        case .didNotAnswer: "its disk didn't answer in time"
        case .failed(let error): "macOS couldn't reach it: \(error.localizedDescription)"
        }
    }
}

extension ProjectArtifacts.Refusal {
    var summary: String {
        switch self {
        case .tooBroad: "a whole home folder or disk is too much to search"
        case .systemFolder: "it is a folder that macOS or every account uses, not a folder of projects"
        case .inTheCloud(.cloud): "it is in a folder that syncs to your other devices through iCloud or another app, which Peel leaves to that app"
        case .inTheCloud(.app(let app, let marker)):
            "it is in a folder \(app.name) syncs to your other devices (its marker is \(Output.plain(Output.path(marker)))), which Peel leaves to that app"
        case .unreachable(let problem): problem.summary
        case .inAPackage: "it is an app or another package, or inside one, and what is inside belongs to it"
        case .neverSearched(.hidden(let name)):
            "Peel doesn't look for projects in \(Output.plain(name)) or anything inside it, since apps and tools keep their own files in hidden folders"
        case .neverSearched(.library):
            "Peel doesn't look for projects in a Library folder or anything inside it, since apps keep their data there"
        case .neverSearched(.filledBy(let folder, let tool)):
            "Peel doesn't look for projects in \(folder) or anything inside it, since \(tool) fills it with what it installs"
        case .insideAnotherFolder(let folder): "it is inside \(Output.path(folder)), which is already on the list"
        case .holdsAnotherFolder(let folder): "it holds \(Output.path(folder)), which is already on the list"
        }
    }
}

extension OrphanConfidence {
    /// The strongest reason behind the judgment, the same one the app shows, in the command line's plain English.
    var summary: String {
        switch reasons.first {
        case .running(let name): "\(Output.plain(name)) is running now, so these may still be in use"
        case .leadsIntoAnAppThatIsGone: "these links lead into an app that is no longer there"
        case .onlyTheName(let name): "only the name ties these to \(Output.plain(name)), which Peel saw installed"
        case .writtenRecently(let date): "modified on \(Output.day(date)), so something may still use these files"
        case .writtenAfterItLeft(let name, let written):
            "modified on \(Output.day(written)), after Peel last saw \(Output.plain(name)) installed, so something may still use these files"
        case .sameMakerStillInstalled: "an app from the same maker is still installed"
        case .appLeft(let name, let lastSeen): "Peel last saw \(Output.plain(name)) installed on \(Output.day(lastSeen))"
        case .untouched(let months): "not modified in \(months) months"
        case .nothingClaimsIt, nil: "nothing installed claims these"
        case .installedForAnAppThatIsGone(let name): "macOS installed these for \(Output.plain(name)), which is gone"
        case .startsAProgramThatIsGone: "these start a program that is no longer there"
        case .loadedByOtherApps: "other apps can load these on their own, such as music apps"
        }
    }

    var levelName: String {
        switch level {
        case .unsure: "unsure"
        case .likely: "likely"
        case .certain: "certain"
        }
    }
}

extension PrivacyReset.Result {
    /// What came of resetting the privacy permissions, in the command line's plain English.
    var summary: String {
        switch self {
        case .reset: "reset"
        case .notKnownToTheSystem: "macOS didn't recognize the app"
        case .refused: "Peel never resets them for this app"
        case .failed(let message): message.isEmpty ? "macOS didn't say why" : "macOS reported: \(Output.plain(message))"
        case .couldNotAsk(let message): Output.plain(message)
        }
    }
}

extension UpdateFailure {
    var summary: String {
        let (subject, object) = switch asked {
        case .appStore: ("The App Store", "the App Store")
        case .server(let host): (Output.plain(host), Output.plain(host))
        }
        return switch cause {
        case .noAnswer(let words): "\(subject) gave no answer: \(Output.plain(words))"
        case .answered(let status):
            switch StatusMeaning(status: status) {
            case .nothingThere: "\(subject) answered \(status): nothing is at that address."
            case .refused: "\(subject) answered \(status): access is refused."
            case .tooManyRequests: "\(subject) answered \(status): it limits how often it answers, and asks Peel to wait."
            case .serverError: "\(subject) answered \(status), an error on the server's side."
            case .other: "\(subject) answered with HTTP status \(status) instead of what Peel asked for."
            }
        case .sentOnTo(let address):
            "\(subject) sent the check on to \(Output.plain(address)), which isn't https, so Peel didn't follow."
        case .tooLarge: "\(subject) sent more than any update feed holds, so Peel stopped reading."
        case .unreadable(let type?):
            "What \(object) sent, marked as \(Output.plain(type)), isn't an answer Peel can read."
        case .unreadable(nil): "What \(object) sent isn't an answer Peel can read."
        case .olderThanFound(let version, let found):
            "The App Store answered \(Output.plain(version)), older than the update to \(Output.plain(found)) it offered before, so its catalog isn't up to date yet."
        case .unlistedAfterAnUpdate:
            "The App Store answered that it doesn't list the app, right after it offered an update, so Peel waits for a second answer."
        }
    }
}

extension HistoryWriteProblem {
    var summary: String {
        switch self {
        case .folderNotWritable(let folder): "this account can't write \(Output.path(folder))"
        case .diskFull(let free, let needed):
            "the disk has \(Output.size(free)) free, and writing History needs \(Output.size(needed))"
        case .freeSpaceNotKnown(let folder):
            "macOS didn't say how much room is free on the disk that holds \(Output.path(folder))"
        case .journalUnreadable(let journal): "\(Output.path(journal)) isn't a journal Peel can read"
        case .journalNotWritable(let journal): "this account can't write \(Output.path(journal))"
        }
    }
}

extension TrashFailure.Reason {
    var summary: String {
        switch self {
        case .guarded(let refusal): refusal?.summary ?? "protected location"
        case .changedSinceScan: "changed since the scan"
        case .changeNotKnown: "couldn't tell in time whether it changed since the scan"
        case .claimedSinceScan: "claimed by an app that is installed now"
        case .lastCopy: "last copy"
        case .notPermitted: "not permitted"
        case .locked: "locked; unlock it in Finder's Get Info"
        case .needsHelper: "needs administrator access"
        case .movedWithoutATrace: "in the Trash where macOS didn't say, so only Finder can put it back"
        case .somethingElseMoved(let name): "something else was at that path; it is in the Trash as \(Output.plain(name))"
        case .historyUnreadable: "History can't be read"
        case .historyCannotBeWritten(let problem?): "History can't be written: \(problem.summary)"
        case .historyCannotBeWritten(nil): "History can't be written"
        case .peelRemovesItself: "Peel is removing itself"
        case .heldOpen(let processes) where processes.count > 1:
            "in use by \(processes.map(Output.plain).joined(separator: ", ")); quit them, then try again"
        case .heldOpen(let processes):
            "in use by \(processes.map(Output.plain).joined(separator: ", ")); quit it, then try again"
        case .heldOpenByAJob(let processes) where processes.count > 1:
            "in use by \(processes.map(Output.plain).joined(separator: ", ")); quit them, or stop them in the Peel app's Background Items if they have no window, then try again"
        case .heldOpenByAJob(let processes):
            "in use by \(processes.map(Output.plain).joined(separator: ", ")); quit it, or stop it in the Peel app's Background Items if it has no window, then try again"
        case .peelRunsFromIt: "Peel runs from here; only Remove Peel, in the app's Settings > General, removes Peel"
        case .heldByAnotherAccount(let processes) where processes.count > 1:
            "in use by \(processes.map(Output.plain).joined(separator: ", ")), running as another account or as the system, which Peel can't quit; stop them in the Peel app's Background Items or with the app's own uninstaller, then try again"
        case .heldByAnotherAccount(let processes):
            "in use by \(processes.map(Output.plain).joined(separator: ", ")), running as another account or as the system, which Peel can't quit; stop it in the Peel app's Background Items or with the app's own uninstaller, then try again"
        case .openForAnotherUser(let processes) where processes.count > 1:
            "in use by \(processes.map(Output.plain).joined(separator: ", ")) in another user's account on this Mac; quit them in that account, then try again"
        case .openForAnotherUser(let processes):
            "in use by \(processes.map(Output.plain).joined(separator: ", ")) in another user's account on this Mac; quit it in that account, then try again"
        case .heldByABuildTool(let tools):
            "in use by \(tools.map(Output.plain).joined(separator: ", ")); run \(BuildDaemon.stopCommands(for: tools).map { "`\($0)`" }.joined(separator: " and ")), then try again"
        case .inUseAsAnInputSource:
            "in use as an input source; in System Settings > Keyboard > Text Input, click Edit beside Input Sources, select it and click Remove, then try again"
        case .inUseByMacOS(let processes): "in use by macOS (\(processes.map(Output.plain).joined(separator: ", ")))"
        case .attachedDiskImage: "a disk image open right now; eject it, then try again"
        case .stillLeadsTo(let target): "still leads to \(Output.plain(target)) on this Mac"
        case .failed(let message): Output.plain(message)
        }
    }
}

extension DeveloperEnvironment.ContentKind {
    var summary: String {
        switch self {
        case .buildData: "build data"
        case .downloads: "downloads"
        case .cache: "cache"
        case .logs: "logs"
        case .deviceSupport: "device support"
        case .archives: "archives"
        case .models: "models"
        case .environments: "installed packages"
        case .keptDownloads: "downloads to install again"
        case .projectState: "an editor's state for a project that is gone"
        }
    }
}
