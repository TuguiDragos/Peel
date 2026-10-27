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

    /// Returns `name` as the last argument of a command to paste, quoted, and after `--` when it begins with `-`,
    /// which `peel` would otherwise read as options whatever the quotes.
    static func lastArgument(_ name: String) -> String {
        plain(name).hasPrefix("-") ? "-- " + quoted(name) : quoted(name)
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
        PathPattern.comparablePath(of: url)
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

    /// What a scan couldn't look into: the folders, and then Full Disk Access when it would open one of them.
    static func unreadableNote(for folders: [URL], needsFullDiskAccess: Bool) -> String {
        let note = "Peel couldn't look inside \(list(named(folders))), so something may be there that isn't listed."
        return needsFullDiskAccess ? note + " " + fullDiskAccessAdvice : note
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
            notes.append("Peel can't read its list of app folders, so the apps in them aren't listed. Start it over in Settings > General > App Folders.")
        }
        if !catalog.unreadable.isEmpty {
            notes.append(unreadableNote(for: catalog.unreadable, needsFullDiskAccess: catalog.needsFullDiskAccess))
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
        }
    }
}

extension RemovalLogProblem {
    var summary: String {
        switch self {
        case .damaged(let setAside): "History was damaged, so it was kept as \(Output.plain(Output.path(setAside))) and started again."
        case .unreadable: "History couldn't be read, so Peel moves nothing until you start it over in the Peel app's History."
        case .couldNotRecord: "History couldn't be saved, so the last removal isn't in it."
        case .couldNotUpdate: "History couldn't be saved, so what was put back is still listed in it."
        }
    }
}

extension RefusalLogProblem {
    var summary: String {
        switch self {
        case .damaged(let setAside):
            "The list of refusals was damaged, so it was kept as \(Output.plain(Output.path(setAside)))"
                + " and started again."
        case .unreadable:
            "The list of refusals couldn't be read, so Peel writes nothing to it until you clear it with"
                + " `peel history --refused --clear` or start it over in the Peel app's History."
        case .couldNotRecord: "The list of refusals couldn't be saved, so what stayed this time isn't in it."
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
        case .nativeMessagingHost: "lets a browser extension run the app"
        case .installerReceipt: "installer receipt"
        case .homebrewReceipt: "Homebrew receipt"
        case .leadsIntoItsHomebrewReceipt: "leads into the Homebrew receipt"
        case .homebrewCask: "Homebrew cask"
        case .managedByTheApp: "managed by the app"
        case .updaterDownloads: "where its updater keeps its downloads"
        case .namedByTheApp: "named by the app's own files"
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
        case .inTheCloud: "syncs to your other devices through iCloud or another app, so moving it would remove it from them too"
        case .holdsDocuments: "holds an app's documents"
        case .holdsALibrary: "holds a photo, music, or video library"
        case .holdsWorkKeptInACache: "holds work an app keeps nowhere else, such as an editor's local history"
        case .couldNotLookInside: "macOS wouldn't let Peel look inside to make sure nothing Peel protects is there"
        }
    }
}

extension HoldBack {
    /// Why the item was held back, the same reason the app's rows give, in the command line's plain English.
    var summary: String {
        switch self {
        case .holdsRepository: "holds a repository"
        case .trackedByGit: "Git tracks files in it"
        case .gitTrackingNotKnown: "in a Git repository whose tracked files couldn't be read"
        case .gitTrackingNotReadInTime: "reading which files Git tracks here took too long"
        case .keepsItsSetup: "keeps the options its build was set up with"
        case .sharedWithEveryone: "belongs to everyone on this Mac"
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
        case .holdsKeys: "holds a wallet or a key Peel protects"
        case .holdsWorkKeptInACache: "holds work an app keeps nowhere else, such as an editor's local history"
        case .insideAnotherAppsFolder: "inside a folder that belongs to macOS or to another installed app"
        case .holdsAnotherAppsData: "holds what another installed app keeps as its own"
        case .beyondTheHelper: "needs an administrator, and Peel's helper may not move it"
        case .leftToItsUninstaller: "removed by the app's own uninstaller once the app is in the Trash"
        case .systemExtension:
            "a system extension macOS installed; moving its app to the Trash in Finder asks macOS to remove it"
        case .systemExtensionGoingAtRestart: "a system extension macOS removes at the next restart"
        case .deletableSystemExtension:
            "a network extension macOS installed; System Settings deletes it: in General > Login Items & Extensions, choose By Category, click the Info button beside Network Extensions, then click the More button beside it and choose Delete Extension"
        case .signInPlugIn: "a plug-in macOS may load at login, left to its maker's uninstaller"
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
        case .keptByAnApp: "in an app's folder in Application Support, and the app may still need it"
        case .appIsRunning: "its app is running and may install this update when it quits"
        case .mayBeTheOnlyCopy: "no installed app's installer and no sign of where it was downloaded from"
        case .encryptedImage: "an encrypted disk image, which holds what you put in it"
        }
    }
}

extension DuplicateFinder.Refusal {
    var summary: String {
        switch self {
        case .appData: "it is app data, the Music or TV app's media folder, or something Peel protects, such as a photo library or a keychain"
        case .inAPackage: "it is an app or another package, or inside one, and what is inside belongs to it"
        case .outsideTheHome: "it is outside your home folder and /Users/Shared, or on a disk Peel can't write to"
        case .insideARepository: "it is a repository, or sits inside one, and Peel leaves repositories alone"
        case .notAFolder: "it isn't a folder Peel can reach"
        }
    }
}

extension ProjectArtifacts.Refusal {
    var summary: String {
        switch self {
        case .tooBroad: "a whole home folder or disk is too much to search"
        case .systemFolder: "it is a folder that macOS or every account uses, not a folder of projects"
        case .inTheCloud: "it is in a folder that syncs to your other devices through iCloud or another app, which Peel leaves to that app"
        case .notAFolder: "it isn't a folder Peel can reach"
        case .inAPackage: "it is an app or another package, or inside one, and what is inside belongs to it"
        case .neverSearched: "it is a hidden folder, a Library, or a folder a tool fills, such as node_modules, or it sits inside one, where apps and tools keep what they install"
        }
    }
}

extension OrphanConfidence {
    /// The strongest reason behind the judgment, the same one the app shows, in the command line's plain English.
    var summary: String {
        switch reasons.first {
        case .running: "something with this identifier is running now"
        case .leadsIntoAnAppThatIsGone: "these links lead into an app that is no longer there"
        case .onlyTheName(let name): "only the name ties these to \(Output.plain(name)), which Peel saw installed"
        case .writtenRecently(let date): "something wrote here on \(Output.day(date))"
        case .writtenAfterItLeft(let name, let written): "something wrote here on \(Output.day(written)), after Peel last saw \(Output.plain(name)) installed"
        case .sameMakerStillInstalled: "an app from the same maker is still installed"
        case .appLeft(let name, let lastSeen): "Peel last saw \(Output.plain(name)) installed on \(Output.day(lastSeen))"
        case .untouched(let months): "\(months) months since anything wrote here"
        case .nothingClaimsIt, nil: "nothing installed claims these"
        case .installedForAnAppThatIsGone(let name): "macOS installed these for \(Output.plain(name)), which is gone"
        case .startsAProgramThatIsGone: "these start a program that is no longer there"
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
        case .notKnownToTheSystem: "macOS couldn't find the app"
        case .refused: "Peel never resets them for this app"
        case .failed(let message): message.isEmpty ? "macOS didn't say why" : "macOS reported: \(Output.plain(message))"
        case .couldNotAsk(let message): Output.plain(message)
        }
    }
}

extension TrashFailure.Reason {
    var summary: String {
        switch self {
        case .guarded(let refusal): refusal?.summary ?? "protected location"
        case .changedSinceScan: "changed since the scan"
        case .claimedSinceScan: "claimed by an app that is installed now"
        case .lastCopy: "last copy"
        case .notPermitted: "not permitted"
        case .locked: "locked; unlock it in Finder's Get Info"
        case .needsHelper: "needs administrator access"
        case .movedWithoutATrace: "in the Trash where macOS didn't say, so only Finder can put it back"
        case .somethingElseMoved(let name): "something else was at that path; it is in the Trash as \(Output.plain(name))"
        case .historyUnreadable: "History can't be read"
        case .historyCannotBeWritten: "History can't be written: the disk is full, or Peel's folder can't be written"
        case .heldOpen(let processes) where processes.count > 1:
            "in use by \(processes.map(Output.plain).joined(separator: ", ")); quit them, or stop them in Background Items if they have no window, then try again"
        case .heldOpen(let processes):
            "in use by \(processes.map(Output.plain).joined(separator: ", ")); quit it, or stop it in Background Items if it has no window, then try again"
        case .peelRunsFromIt: "Peel runs from here; only Remove Peel, in the app's Settings > General, removes Peel"
        case .heldByAnotherAccount(let processes) where processes.count > 1:
            "in use by \(processes.map(Output.plain).joined(separator: ", ")), running as another account or as the system, which Peel can't quit; stop them in Background Items or with the app's own uninstaller, then try again"
        case .heldByAnotherAccount(let processes):
            "in use by \(processes.map(Output.plain).joined(separator: ", ")), running as another account or as the system, which Peel can't quit; stop it in Background Items or with the app's own uninstaller, then try again"
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
