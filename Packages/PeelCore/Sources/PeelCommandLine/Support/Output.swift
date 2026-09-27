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

    /// Replaces every control character with `?` (`PlainText`), for names and paths from other people's bundles.
    static func plain(_ text: String) -> String {
        PlainText.of(text)
    }

    /// Returns `name` so the reader can paste it into a command: in single quotes when it contains a space.
    static func quoted(_ name: String) -> String {
        let name = plain(name)
        return name.contains(" ") ? "'\(name.replacingOccurrences(of: "'", with: "'\\''"))'" : name
    }

    /// Writes `text` to standard output unchanged, for output that already ends in a newline. When the write fails
    /// (a closed stdout, a full disk), the tool exits with status 1. `FileHandle.write(_:)` would instead raise an
    /// exception Swift can't catch, and the tool would crash.
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
    /// every other control character is replaced with `?`.
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

    static let fullDiskAccessNote = "Some folders couldn't be read. Give your terminal app Full Disk Access in System Settings to see everything."

    /// Whether the user can answer a question: standard input and standard error must both be a terminal. The
    /// question goes to standard error, and with that redirected the user would see only a waiting cursor.
    static var canAsk: Bool { isatty(STDIN_FILENO) == 1 && isatty(STDERR_FILENO) == 1 }

    /// Throws when the user can't be asked. Commands call this from `validate()`, where ArgumentParser knows which
    /// subcommand was typed and so prints that subcommand's usage.
    static func requireConfirmable() throws {
        guard canAsk else { throw ValidationError("Add --yes to confirm when Peel can't ask.") }
    }

    /// Exit code 2, for when the user answers no. `CleanExit` would report success, and
    /// `peel uninstall Foo && next-step` would then run `next-step` anyway.
    static let declined = ExitCode(2)

    /// Asks `question` on standard error, which reaches the terminal even when the output goes to a file. Throws
    /// `declined` unless the user answers y or yes.
    static func confirm(_ question: String) throws {
        try requireConfirmable()
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
        case .notAllowed: "Peel won't write there"
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
        case .installerReceipt: "installer receipt"
        case .homebrewCask: "Homebrew cask"
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

extension HoldBack {
    /// Why the item was held back, the same reason the app's rows give, in the command line's plain English.
    var summary: String {
        switch self {
        case .holdsRepository: "holds a repository"
        case .sharedWithEveryone: "belongs to everyone on this Mac"
        case .namedLikeTheApp: "claimed on the app's name alone"
        case .holdsAnExclusion: "holds something you excluded"
        case .notMeasured: "not measured in time"
        case .couldNotBeRead: "macOS wouldn't let Peel read inside"
        case .holdsDocuments: "holds the app's documents"
        case .holdsALibrary: "holds a photo, music, or video library"
        case .holdsAWallet: "holds a wallet or a signing key"
        case .holdsKeys: "holds a wallet or a key Peel protects"
        case .insideAnotherAppsFolder: "inside another app's folder"
        case .beyondTheHelper: "needs an administrator, and Peel's helper may not move it"
        }
    }
}

extension ProjectArtifacts.Refusal {
    var summary: String {
        switch self {
        case .tooBroad: "a whole home folder or disk is too much to search"
        case .inTheCloud: "it is in a cloud folder, which Peel leaves to the app that syncs it"
        case .notAFolder: "it isn't a folder Peel can reach"
        }
    }
}

extension OrphanConfidence {
    /// The strongest reason behind the judgment, the same one the app shows, in the command line's plain English.
    var summary: String {
        switch reasons.first {
        case .running: "something with this identifier is running now"
        case .leadsIntoAnAppThatIsGone: "these links lead into an app that is no longer there"
        case .writtenRecently(let date): "something wrote here on \(Output.day(date))"
        case .writtenAfterItLeft(let name, let written): "something wrote here on \(Output.day(written)), after Peel last saw \(Output.plain(name)) installed"
        case .sameMakerStillInstalled: "an app from the same maker is still installed"
        case .appLeft(let name, let lastSeen): "Peel last saw \(Output.plain(name)) installed on \(Output.day(lastSeen))"
        case .untouched(let months): "\(months) months since anything wrote here"
        case .nothingClaimsIt, nil: "nothing installed claims these"
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
        case .protectedLocation: "protected location"
        case .changedSinceScan: "changed since the scan"
        case .claimedSinceScan: "claimed by an app that is installed now"
        case .lastCopy: "last copy"
        case .notPermitted: "not permitted"
        case .needsHelper: "needs administrator access"
        case .movedWithoutATrace: "in the Trash where macOS didn't say, so only Finder can put it back"
        case .somethingElseMoved(let name): "something else was at that path; it is in the Trash as \(Output.plain(name))"
        case .historyUnreadable: "History can't be read"
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
        case .deviceSupport: "device support, kept by default"
        case .archives: "archives, kept by default"
        case .models: "models, kept by default"
        case .environments: "installed packages, kept by default"
        case .keptDownloads: "downloads to install again, kept by default"
        }
    }
}
