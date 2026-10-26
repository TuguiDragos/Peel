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
    }

    static func way(cask: HomebrewPackage?, homebrewKnowsItsApps: Bool) -> Way {
        if let cask { return .homebrew("brew uninstall --zap --cask \(cask.name)") }
        return homebrewKnowsItsApps ? .removePeel : .waitingForHomebrew
    }

    static var removeCommand: String {
        "sudo rm -f /usr/local/bin/peel"
    }

    /// Whether Remove Peel would leave `/usr/local/bin/peel` while it is Peel's own tool: only an administrator can
    /// move it, and the helper that would is not enabled. For another program's `peel`, `removeCommand` would delete
    /// a file that is not Peel's.
    func leavesCommandLineTool(helper status: PrivilegedHelper.Status) -> Bool {
        let embedded = Bundle.main.bundleURL.appending(path: "Contents/Helpers/peel")
        return status != .enabled && CommandLineTool.standing(embedded: embedded) == .installed
            && FileAccess.requiresPrivilegesToRemove(URL(filePath: CommandLineTool.path))
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
            tell(.stayed(String(localized: "Peel couldn’t read its own files.")), words)
            return
        }
        let exclusions = ExclusionsStore.shared.exclusions
        let plan = await Uninstallation.prepare(app, installedApps: installedApps, exclusions: exclusions)
        let urls = plan.unreviewedSelection
        let isOnAReadOnlyVolume = SelfRemoval.isOnAReadOnlyVolume(bundleURL)
        if let block = SelfRemoval.block(
            selection: urls, isExcluded: plan.isExcluded, isOnAReadOnlyVolume: isOnAReadOnlyVolume
        ) {
            tell(.stayed(Self.explanation(of: block)), words)
            return
        }

        let language = Bundle.main.preferredLocalizations.first
        let outcome = await SelfRemoval.remove(
            urls,
            links: plan.unreviewedLinks,
            app: bundleURL,
            folder: PeelFolder.url,
            steps: SelfRemoval.Steps(
                helperIsRegistered: { helper.status == .enabled || helper.status == .requiresApproval },
                helperIsEnabled: { helper.status == .enabled },
                uninstallHelper: { await helper.uninstall()?.reason },
                work: work
            ),
            using: TrashService(exclusions: exclusions),
            recording: record
        )
        guard case .moved(let moved, let stayed, let opensAtLogin) = outcome else {
            if case .stayed(let stay) = outcome {
                tell(.stayed(Self.failure(for: stay)), words)
            }
            return
        }
        SelfRemoval.endExtensions(runningFrom: moved.trashedURL)
        words = language.flatMap {
            Bundle(url: moved.trashedURL.appending(path: "Contents/Resources/\($0).lproj", directoryHint: .isDirectory))
        }
        _ = await DockTiles().takeOut([bundleURL], remembering: false)
        var lines = stayed.map { "\($0.url.abbreviatedPath)\n\($0.reason.explanation(in: words))" }
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
            String(localized: "Peel is running from a copy macOS made because it is still marked as downloaded, or from its disk image, and that copy can’t be moved. Quit Peel, move it to the Applications folder, open it there, and choose Remove Peel again.")
        case .needsAnAdministrator:
            String(localized: "Peel won’t move itself from here: its folder needs an administrator. Drag it to the Trash in Finder, which asks for an administrator.")
        }
    }

    private static func failure(for stay: SelfRemoval.Stay) -> String {
        let helperStayed = String(localized: "The helper couldn’t be removed, so Peel stayed where it was.")
        switch stay {
        case .helperIsNotThisAccounts:
            return helperStayed
        case .helperStayed(let reason, let ledger):
            let reason = reason ?? helperStayed
            return ledger == .moved ? "\(reason)\n\n\(ledgerInTheTrash)" : reason
        case .appStayed(let failures, let ledger):
            let lines = failures.map { "\($0.url.abbreviatedPath)\n\($0.reason.explanation)" }
            return (lines + (ledger == .moved ? [ledgerInTheTrash] : [])).joined(separator: "\n\n")
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
