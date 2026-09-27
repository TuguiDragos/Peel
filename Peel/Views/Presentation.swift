import PeelCore
import SwiftUI

extension MatchReason {
    var title: LocalizedStringResource {
        switch self {
        case .bundleIdentifier: "The app’s identifier"
        case .embeddedBundleIdentifier: "Helper or extension of the app"
        case .applicationGroup: "A group the app belongs to"
        case .bundleIdentifierPrefix: "Starts with the identifier of the app or of something inside it"
        case .name: "Same name as the app"
        case .teamIdentifier: "Starts with the same maker’s team ID"
        case .vendorPrefix: "Starts with the same maker’s identifier"
        case .namePrefix: "Starts with the app’s name"
        case .launchdJob: "Runs a program inside the app"
        case .linksToTheApp: "Leads to a tool inside the app"
        case .installerReceipt: "The app’s installer receipt"
        case .homebrewCask: "Listed by the Homebrew cask"
        }
    }
}

extension Greeting {
    var title: LocalizedStringResource {
        switch self {
        case .morning: "Good morning"
        case .afternoon: "Good afternoon"
        case .evening: "Good evening"
        }
    }
}

extension FileKind {
    var title: LocalizedStringResource {
        switch self {
        case .any: "Any kind"
        case .documents: "Documents"
        case .images: "Images"
        case .movies: "Movies"
        case .audio: "Audio"
        case .archives: "Archives"
        case .diskImages: "Disk images"
        }
    }
}

extension SearchLocation.Kind {
    /// The name of an item's kind, shown in the column beside its path. A path like
    /// `/var/folders/…/C/dev.warp.Warp-Stable` says little on its own, while "Caches" says what would be lost.
    /// ByHost preferences are shown as "Preferences": the path already shows the difference.
    var title: LocalizedStringResource {
        switch self {
        case .applicationSupport: "Application Support"
        case .applicationScripts: "Application Scripts"
        case .caches: LocalizedStringResource("Caches (Library folder)", defaultValue: "Caches")
        case .containers: "Container"
        case .groupContainers: "Group Container"
        case .preferences, .preferencesByHost: "Preferences"
        case .savedApplicationState: "Saved Windows"
        case .recentDocuments: "Recent Documents"
        case .logs: LocalizedStringResource("Logs (Library folder)", defaultValue: "Logs")
        case .httpStorages: "Web Storage"
        case .webKit: "WebKit Data"
        case .cookies: "Cookies"
        case .launchAgents: "Launch Agent"
        case .launchDaemons: "Launch Daemon"
        case .privilegedHelperTools: "Helper Tool"
        case .plugIns: "Plug-in"
        case .receipts: "Installer Receipt"
        case .library: "Library Folder"
        case .temporaryItems: "Temporary Files"
        case .commandLineTools: "Command-Line Tool"
        case .elsewhere: "Elsewhere"
        case .sharedFolder: "Shared Folder"
        case .hiddenHomeFiles: "Hidden Item"
        case .homeFolder: "Home Folder"
        }
    }

    var symbolName: String {
        switch self {
        case .applicationSupport: "folder"
        case .applicationScripts: "applescript"
        case .caches: "archivebox"
        case .temporaryItems: "hourglass"
        case .commandLineTools: "terminal"
        case .elsewhere: "mappin.and.ellipse"
        case .containers, .groupContainers: "shippingbox"
        case .preferences, .preferencesByHost: "gearshape"
        case .savedApplicationState: "macwindow"
        case .recentDocuments: "clock.arrow.circlepath"
        case .logs: "doc.text"
        case .httpStorages, .webKit, .cookies: "globe"
        case .launchAgents, .launchDaemons: "gearshape.2"
        case .privilegedHelperTools: "lock.shield"
        case .plugIns: "powerplug"
        case .receipts: "doc.text.below.ecg"
        case .library: "building.columns"
        case .sharedFolder: "person.2"
        case .hiddenHomeFiles: "eye.slash"
        case .homeFolder: "house"
        }
    }
}

extension TrashFailure.Reason {
    /// What went wrong with one item of a removal, in words for the user who asked to move it.
    var explanation: String {
        switch self {
        case .protectedLocation: String(localized: "Peel won’t move this: it is protected, or your exclusions in Settings keep it where it is.")
        case .changedSinceScan: String(localized: "It changed after Peel looked at it. Scan again to review it.")
        case .claimedSinceScan: String(localized: "Peel couldn’t confirm it is still nobody’s: an installed app may claim it now. Scan again to review it.")
        case .lastCopy: String(localized: "The copy Peel was keeping has changed or moved since the scan, so this one may be the last.")
        case .notPermitted: String(localized: "macOS didn’t allow it.")
        case .needsHelper: String(localized: "It needs administrator access, which Peel’s helper provides.")
        case .movedWithoutATrace: String(localized: "It is in the Trash, but macOS didn’t say where, so it can only be put back from Finder.")
        case .somethingElseMoved(let name): String(localized: "Something else was at that path by the time it moved. It is in the Trash as \(name), and Finder can put it back.")
        case .historyUnreadable: String(localized: "Peel couldn’t read History, and it moves nothing it can’t put back.")
        case .heldOpen(let processes):
            String(localized: "Files in it are still open in \(processes.formatted(.list(type: .and))), so Peel left it where it is.")
        case .failed(let message): FixedSentence.translated(message)
        }
    }
}

extension PrivacyReset.Result {
    /// Why the app's privacy permissions were not reset, or nil when they were.
    var explanation: String? {
        switch self {
        case .reset: nil
        case .notKnownToTheSystem: String(localized: "macOS couldn’t find the app, so what it was allowed to access is still on record.")
        case .refused: String(localized: "Peel never resets them for this app.")
        case .failed(let message): message.isEmpty ? String(localized: "macOS didn’t say why.") : String(localized: "macOS reported: \(message)")
        case .couldNotAsk(let message): FixedSentence.translated(message)
        }
    }
}

extension ProjectArtifacts.Refusal {
    /// Why a chosen folder can't be searched for projects. It is shown where the folder was chosen, rather
    /// than as an empty list.
    var explanation: String {
        switch self {
        case .tooBroad: String(localized: "A whole home folder or disk is too much to search. Choose the folder your projects are in.")
        case .inTheCloud: String(localized: "It is in iCloud Drive or another cloud folder, which Peel leaves to the app that syncs it.")
        case .notAFolder: String(localized: "It isn’t a folder Peel can reach. A disk that isn’t connected looks like this too.")
        }
    }
}

extension RestoreFailure {
    /// Why one item stayed in the Trash. Shown beside the item, since a batch can fail for several reasons.
    var explanation: String {
        switch self {
        case .missingFromTrash: String(localized: "It is no longer in the Trash, so there is nothing to put back.")
        case .alreadyThere: String(localized: "Something is already there, and Peel never replaces it.")
        case .needsHelper: String(localized: "It needs administrator access, which Peel’s helper provides.")
        case .notAllowed: String(localized: "Peel never puts anything back there.")
        case .failed(let message): FixedSentence.translated(message)
        }
    }
}

extension CloudRefusal {
    /// Why a file's local copy was not freed. Freeing deletes nothing, since the file stays in iCloud, so no
    /// way back is offered.
    var explanation: String {
        switch reason {
        case .changedSinceScan: String(localized: "It isn’t as it was when Peel looked at it: it may have been edited, stopped syncing, or been freed already, so Peel left it alone.")
        case .excluded: String(localized: "Excluded in Settings")
        case .failed(let message): message
        }
    }
}

extension HoldBack {
    /// Why Peel did not select an item, or leaves it where it is. It is shown in the note beside the row, with
    /// the reason for the match.
    var explanation: LocalizedStringResource {
        switch self {
        case .holdsRepository:
            "Not selected: there is a repository inside, so this folder may hold work that was committed and never pushed anywhere."
        case .sharedWithEveryone:
            "Not selected: /Users/Shared belongs to every account on this Mac rather than to one app."
        case .namedLikeTheApp:
            "Not selected: only the name matches, and a folder here may be another program’s, holding work you rely on."
        case .holdsAnExclusion:
            "Left alone: something you excluded in Settings is inside, and moving this would take it along."
        case .notMeasured:
            "Not selected: this folder took too long to measure, so Peel doesn’t know how big it is or what is inside."
        case .couldNotBeRead:
            "Not selected: macOS wouldn’t let Peel read inside, so what is in there isn’t known. If Peel doesn’t have Full Disk Access yet, giving it in System Settings may let it see."
        case .holdsDocuments:
            "Left alone: the app’s own Documents folder is inside and may hold what you made with it. Peel never removes that."
        case .holdsALibrary:
            "Left alone: a photo, music, or video library is inside, so Peel leaves this folder where it is."
        case .holdsAWallet:
            "Not selected: a wallet or a signing key is inside. Once the Trash is emptied, what it opens is gone for good unless you have a backup."
        case .holdsKeys:
            "Left alone: a wallet or a key Peel protects is inside, so Peel leaves this folder where it is."
        case .insideAnotherAppsFolder:
            "Not selected: only the name matches, and it sits inside a folder that belongs to macOS or to another installed app, which may be keeping it for itself."
        case .beyondTheHelper:
            "Left alone: only an administrator can move this, and Peel’s helper isn’t allowed to move it from here."
        case .keptByMacOS:
            "Not selected: macOS keeps this cache for its own services, which may be using it right now."
        case .openedFromMail:
            "Not selected: Mail keeps a copy here of each attachment you open, and one you edited may exist nowhere else."
        }
    }
}

extension OrphanConfidence {
    /// The strongest thing Peel can say about these files, in one line.
    var summary: Text {
        text(for: reasons.first)
    }

    /// The badge on a group's page, or nil when it would add nothing: the summary when Peel is unsure, or
    /// else how long nothing has written there. That Peel saw the app leave is said in a line of its own, so a
    /// write after it left is told by its date alone.
    var badge: Text? {
        if case .writtenAfterItLeft(_, let written) = reasons.first { return wroteHere(written) }
        if level == .unsure { return summary }
        return reasons.first { if case .untouched = $0 { true } else { false } }.map(text(for:))
    }

    private func wroteHere(_ date: Date) -> Text {
        Text("Something wrote here \(date, format: .relative(presentation: .named))")
    }

    private func text(for reason: Reason?) -> Text {
        guard let reason else { return Text("No installed app claims these") }
        return switch reason {
        case .running:
            Text("Something with this identifier is running now")
        case .leadsIntoAnAppThatIsGone:
            Text("These links lead into an app that is no longer there")
        case .onlyTheName(let name):
            Text("Only the name ties these to \(name), which Peel saw installed")
        case .writtenRecently(let date):
            wroteHere(date)
        case .writtenAfterItLeft(let name, let written):
            Text("Something wrote here \(written, format: .relative(presentation: .named)), after Peel last saw \(name) installed")
        case .sameMakerStillInstalled:
            Text("An app from the same maker is still installed")
        case .appLeft(let name, let lastSeen):
            Text("Peel last saw \(name) installed \(lastSeen, format: .relative(presentation: .named))")
        case .untouched(let months):
            Text("^[\(months) month](inflect: true) since anything wrote here")
        case .nothingClaimsIt:
            Text("No installed app claims these")
        }
    }

    /// Orange only when Peel is unsure. Being sure is the usual case here and needs no color.
    var tint: Color {
        level == .unsure ? .orange : .secondary
    }

    var systemImage: String {
        switch level {
        case .unsure: "exclamationmark.triangle"
        case .likely: "questionmark.circle"
        case .certain: "checkmark.seal"
        }
    }

}

extension URL {
    var abbreviatedPath: String {
        (path(percentEncoded: false) as NSString).abbreviatingWithTildeInPath
    }
}

extension Int64 {
    var byteCount: String {
        ByteCounts.string(for: self)
    }
}

/// Remembers formatted byte counts. Formatting one is the most expensive step in drawing a row, and a long
/// list redraws many rows at a time.
///
/// `ByteCountFormatter` is faster but writes different strings ("Zero KB" and "999 bytes" where the format
/// style writes "Zero kB" and "1 kB"), so the format style is kept and its answers are cached.
@MainActor
private enum ByteCounts {
    private static var known: [Int64: String] = [:]
    /// The most answers kept, enough for a long list. When full, the cache is emptied rather than left to
    /// grow without bound.
    private static let limit = 8192
    private static var watchesLocale = false

    static func string(for value: Int64) -> String {
        watchLocale()
        if let text = known[value] { return text }
        if known.count >= limit { known.removeAll(keepingCapacity: true) }
        let text = value.formatted(.byteCount(style: .file))
        known[value] = text
        return text
    }

    /// Empties the cache when the locale changes. Reading the locale on every call would cost more than the
    /// lookup it guards.
    private static func watchLocale() {
        guard !watchesLocale else { return }
        watchesLocale = true
        NotificationCenter.default.addObserver(
            forName: NSLocale.currentLocaleDidChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in known.removeAll(keepingCapacity: true) }
        }
    }
}

extension Int64? {
    /// The size, or "Unknown" when it is not known, such as for a folder that did not answer in time. An
    /// unknown size never reads as zero.
    var byteCount: String {
        self?.byteCount ?? String(localized: "Unknown")
    }
}

extension SizeTotal {
    var text: String {
        if isComplete { return known.byteCount }
        return known > 0 ? String(localized: "Over \(known.byteCount)") : String(localized: "Unknown")
    }

    /// The form `text` is in, used as the view's identity: within one form the digits roll, while a change to
    /// or from a word, or "Over" coming or going, fades instead.
    var textKind: String {
        guard known > 0 else { return text }
        return isComplete ? "exact" : "over"
    }
}

extension Int {
    /// A count in compact form, such as "12K", for a lifetime total where six digits would not fit.
    var shortCount: String {
        formatted(.number.notation(.compactName))
    }
}

extension LocalizedStringResource {
    /// "Excluded in Settings", said of an app. It has its own key because in Spanish, French, Romanian,
    /// Polish, and Czech the words agree with the feminine word for an app. The plain key is said of a file,
    /// a folder, or a package.
    static let excludedApp = LocalizedStringResource(
        "Excluded in Settings (app)", defaultValue: "Excluded in Settings",
        comment: "Shown for an app the user excluded in Settings. Use the form that agrees with the word for an app."
    )
}
