import AppKit
import Foundation
import Observation
import PeelCore

/// Peel removing itself: its own files and the app, once the helper and the login item are gone. The app holds one,
/// so a removal goes on, and is told, whatever page or window started it.
@Observable
final class SelfUninstall {
    private(set) var isRunning = false
    /// Where Peel's words are read once it is in the Trash: the folder of the language it was using, there, since the
    /// main bundle still names the place Peel left. Nil reads them from the main bundle.
    private(set) var words: Bundle?
    /// Says what came of a removal that didn't end with Peel gone: the app's own alert, which a test stands in for.
    private let tell: @MainActor (Report, _ words: Bundle?) -> Void

    enum Report: Equatable {
        case stayed(String)
        /// Peel is in the Trash, and what stayed behind, after which Peel quits.
        case leftBehind(String)
    }

    init(tell: @escaping @MainActor (Report, _ words: Bundle?) -> Void = SelfUninstall.alert) {
        self.tell = tell
    }

    /// The alert of the app, shown wherever the person is, since the page that started the removal may be gone.
    static func alert(_ report: Report, words: Bundle?) {
        let alert = NSAlert()
        switch report {
        case .stayed(let reason):
            alert.messageText = String(localized: "Peel couldn’t remove itself.")
            alert.informativeText = reason
            alert.runModal()
        case .leftBehind(let lines):
            alert.messageText = String(localized: "Peel is in the Trash, but a few things stayed behind.", bundle: words)
            alert.informativeText = lines
            alert.addButton(withTitle: String(localized: "Quit Peel", bundle: words))
            alert.runModal()
            quit()
        }
    }

    /// Runs `removal` alone: never beside another removal of Peel, nor while Peel moves something, puts something
    /// back, or runs Homebrew, whose History and folder Remove Peel takes. A quit is refused meanwhile, since Peel ends
    /// itself once it has gone.
    func runAlone(quitGuard: QuitGuard = .shared, _ removal: () async -> Void) async {
        guard !isRunning else { return }
        guard !quitGuard.hasWorkUnderWay else {
            tell(.stayed(String(localized: "Peel is still moving something, putting something back, or running Homebrew. Try again once it’s done.")), words)
            return
        }
        isRunning = true
        defer { isRunning = false }
        await quitGuard.runRefusingQuit(removal)
    }

    /// How this copy of Peel is removed: with Homebrew's command when Homebrew installed it, which it goes on listing
    /// otherwise, or with Remove Peel.
    enum Way: Equatable {
        case homebrew(String)
        case removePeel
        /// Homebrew hasn't said yet whether it installed this copy, which would then look like any other.
        case waitingForHomebrew
        /// Homebrew's reading ended without saying, for the reason its page gives.
        case homebrewDidNotAnswer(HomebrewLibrary.Unanswered)

        /// Whether Remove Peel waits until Homebrew says whether it installed this copy.
        var waitsForHomebrew: Bool {
            switch self {
            case .waitingForHomebrew, .homebrewDidNotAnswer: true
            case .homebrew, .removePeel: false
            }
        }
    }

    /// `brew` is the word that runs the person's Homebrew in Terminal (`Homebrew.wordForTerminal`).
    static func way(
        cask: HomebrewPackage?, brew: String, homebrewKnowsItsApps: Bool,
        unanswered: HomebrewLibrary.Unanswered? = nil
    ) -> Way {
        if let cask { return .homebrew("\(brew) uninstall --zap --cask \(Homebrew.lastWord(naming: cask.name))") }
        if homebrewKnowsItsApps { return .removePeel }
        return unanswered.map(Way.homebrewDidNotAnswer) ?? .waitingForHomebrew
    }

    /// Whether Peel can't remove itself from this account: its helper is registered, and only an administrator may
    /// change it.
    static func waitsForAnAdministrator(isAdministrator: Bool, status: PrivilegedHelper.Status) -> Bool {
        !isAdministrator && status.isRegistered
    }

    static var onlyAnAdministrator: String {
        String(localized: "Only an administrator can remove Peel’s helper, so Peel can’t remove itself from this account. Log in as an administrator and choose Remove Peel there.")
    }

    /// What Remove Peel's question says goes before the files: the helper while it is registered, since every
    /// account on this Mac shares it, and the login item while it is on.
    static func whatGoesFirst(helperIsRegistered: Bool, opensAtLogin: Bool) -> String? {
        switch (helperIsRegistered, opensAtLogin) {
        case (true, true):
            String(localized: "Peel removes its helper, which serves every account on this Mac, so it goes for all of them, and stops opening at login.")
        case (true, false):
            String(localized: "Peel removes its helper, which serves every account on this Mac, so it goes for all of them.")
        case (false, true): String(localized: "Peel stops opening at login.")
        case (false, false): nil
        }
    }

    static var removeCommand: String {
        "sudo rm -f /usr/local/bin/peel"
    }

    /// Whether removing Peel `way` would leave `/usr/local/bin/peel` while it is Peel's own tool. For another
    /// program's `peel`, `removeCommand` would delete a file that is not Peel's.
    func leavesCommandLineTool(way: Way, helper status: PrivilegedHelper.Status) -> Bool {
        let embedded = Bundle.main.bundleURL.appending(path: "Contents/Helpers/peel")
        return Self.leavesCommandLineTool(
            way: way,
            helper: status,
            standing: CommandLineTool.standing(embedded: embedded),
            needsAnAdministrator: FileAccess.requiresPrivilegesToRemove(URL(filePath: CommandLineTool.path))
        )
    }

    /// A link to Peel's tool that only an administrator can move stays when Homebrew removes Peel, since its command
    /// runs no step of Peel's, and when Remove Peel does while the helper that would take it isn't enabled.
    static func leavesCommandLineTool(
        way: Way, helper status: PrivilegedHelper.Status, standing: CommandLineTool.Standing,
        needsAnAdministrator: Bool
    ) -> Bool {
        guard standing == .installed, needsAnAdministrator else { return false }
        if case .homebrew = way { return true }
        return status != .enabled
    }

    /// What Remove Peel asks of the helper along the way. Whether it is registered comes from macOS at that moment,
    /// never from the model's last answer, which a change of the helper under way leaves behind.
    static func steps(
        helper: HelperModel,
        work: StandingWork,
        status: @escaping () async -> PrivilegedHelper.Status = PrivilegedHelper.currentStatus
    ) -> SelfRemoval.Steps {
        SelfRemoval.Steps(
            helperIsRegistered: { await status().isRegistered },
            helperIsEnabled: { await status() == .enabled },
            uninstallHelper: { await helper.uninstall()?.reason },
            work: work
        )
    }

    /// Removes Peel. The plan is made first, so a plan that cannot be made leaves Peel as it was, and then
    /// `SelfRemoval.remove` takes the steps.
    func run(
        installedApps: [InstalledApp],
        helper: HelperModel,
        pausing work: StandingWork,
        recording record: (TrashResult) async -> Void = { _ in }
    ) async {
        await runAlone {
            await remove(installedApps: installedApps, helper: helper, pausing: work, recording: record)
        }
    }

    private func remove(
        installedApps: [InstalledApp],
        helper: HelperModel,
        pausing work: StandingWork,
        recording record: (TrashResult) async -> Void
    ) async {
        let bundleURL = Bundle.main.bundleURL
        guard let app = await AppLibrary.inspect(bundleURL) else {
            tell(.stayed(AppInspector.whyUnreadable(bundleURL).explanation(at: bundleURL)), words)
            return
        }
        let exclusions = ExclusionsStore.shared.exclusions
        let plan = await Uninstallation.prepare(app, installedApps: installedApps, exclusions: exclusions)
        let urls = plan.unreviewedSelection
        if let block = SelfRemoval.block(selection: urls, isExcluded: plan.isExcluded, app: bundleURL) {
            tell(.stayed(Self.explanation(of: block)), words)
            return
        }

        let language = Bundle.main.preferredLocalizations.first
        let outcome = await SelfRemoval.remove(
            urls,
            links: plan.unreviewedLinks,
            app: bundleURL,
            folder: PeelFolder.url,
            steps: Self.steps(helper: helper, work: work),
            using: TrashService(exclusions: exclusions),
            recording: record
        )
        guard case .moved(let moved, let stayed, let opensAtLogin) = outcome else {
            if case .stayed(let stay) = outcome {
                tell(.stayed(Self.failure(for: stay)), words)
            }
            return
        }
        words = language.flatMap {
            Bundle(url: moved.trashedURL.appending(path: "Contents/Resources/\($0).lproj", directoryHint: .isDirectory))
        }
        _ = await DockTiles().takeOut([bundleURL], remembering: false)
        var lines = RemovalFailureAlert.underTheirReasons(
            stayed.map { ($0.url.abbreviatedPath, $0.reason.explanation(in: words)) }, limit: nil
        )
        if opensAtLogin {
            lines.append(String(localized: "Peel is still set to open at login: remove it in System Settings > General > Login Items & Extensions.", bundle: words))
        }
        guard lines.isEmpty else {
            tell(.leftBehind(lines.joined(separator: "\n\n")), words)
            return
        }
        Self.quit()
    }

    static func explanation(of block: SelfRemoval.Block) -> String {
        switch block {
        case .excluded:
            String(localized: "Peel won’t move itself: it is excluded in Settings > Exclusions. Take it off the list there, then choose Remove Peel again.")
        case .readOnlyCopy:
            String(localized: "Peel runs from a copy it cannot move. Quit Peel, move it to the Applications folder, open it there, and choose Remove Peel again.")
        case .needsAnAdministrator:
            String(localized: "Peel will not move itself from here: its folder needs an administrator. Log in as an administrator and choose Remove Peel there. Dragging Peel to the Trash in Finder leaves its helper, its login item, and its files behind.")
        case .needsItsOwner(let owner):
            String(localized: "Peel will not move itself from here: it belongs to the account \(owner). Log in to that account and choose Remove Peel there. Dragging Peel to the Trash in Finder leaves its helper, its login item, and its files behind.")
        case .leftToFinder:
            String(localized: "Peel will not move itself from here: this account is not allowed to move it. Dragging Peel to the Trash in Finder leaves its helper, its login item, and its files behind.")
        }
    }

    private static func failure(for stay: SelfRemoval.Stay) -> String {
        let helperStayed = String(localized: "The Peel helper could not be removed, so Peel stayed where it was.")
        switch stay {
        case .helperIsNotThisAccounts:
            return onlyAnAdministrator
        case .helperStayed(let reason, let ledger):
            let reason = reason ?? helperStayed
            return ledger == .moved ? "\(reason)\n\n\(ledgerInTheTrash)" : reason
        case .appStayed(let failures, let ledger, let helperIsGone):
            let lines = RemovalFailureAlert.underTheirReasons(
                failures.map { ($0.url.abbreviatedPath, $0.reason.explanation) }, limit: nil
            )
            let helper = helperIsGone
                ? [String(localized: "The Peel helper is already removed, for every account. Install it again in Settings > Helper.")]
                : []
            return (lines + (ledger == .moved ? [ledgerInTheTrash] : []) + helper).joined(separator: "\n\n")
        }
    }

    /// Said when Peel stays after the helper's ledger went to the Trash: without it, the helper puts back nothing it
    /// moved, now or once it is installed again.
    private static var ledgerInTheTrash: String {
        let folder = PrivilegedHelper.ledgerFolder
        return String(localized: "Peel’s helper keeps a record of what it moves, and that record is already in the Trash, as \(folder.lastPathComponent). Until it is back in \(folder.deletingLastPathComponent().abbreviatedPath), History can’t put back what the helper moved.")
    }

    /// Exits at once with `_exit`: `NSApp.terminate` would let AppKit write the window's frame and saved state again,
    /// and `exit` runs the handlers that write the cookie store at exit, all of which were just removed.
    static func quit() {
        _exit(EXIT_SUCCESS)
    }
}
