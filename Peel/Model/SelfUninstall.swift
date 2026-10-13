import AppKit
import Foundation
import Observation
import PeelCore

/// Peel removing itself: its own files and the app, once the helper and the login item are gone.
@Observable
final class SelfUninstall {
    private(set) var isRunning = false
    var failure: String?
    /// What stayed after the app itself moved to the Trash: files, and a login item. Peel is running from the Trash by
    /// then, so the alert that lists them has a single button, which quits.
    private(set) var leftBehind: String?
    /// Where Peel's words are read once it is in the Trash: the folder of the language it was using, there, since the
    /// main bundle still names the place Peel left. Nil reads them from the main bundle.
    private(set) var words: Bundle?

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
    /// `SelfRemoval.remove` takes the steps. A quit is refused meanwhile, since Peel ends itself once it has gone.
    func run(
        installedApps: [InstalledApp],
        helper: HelperModel,
        pausing work: StandingWork,
        recording record: (TrashResult) async -> Void = { _ in }
    ) async {
        isRunning = true
        defer { isRunning = false }
        await QuitGuard.shared.runRefusingQuit {
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
            failure = String(localized: "Peel couldn’t read its own files.")
            return
        }
        let exclusions = ExclusionsStore.shared.exclusions
        let plan = await Uninstallation.prepare(app, installedApps: installedApps, exclusions: exclusions)
        let urls = plan.unreviewedSelection
        guard !urls.isEmpty else {
            failure = String(localized: "Peel won’t move itself from here: its folder needs an administrator, or Peel is excluded in Settings. Drag it to the Trash in Finder, which asks for an administrator when one is needed.")
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
                failure = Self.failure(for: stay)
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
            leftBehind = lines.joined(separator: "\n\n")
            return
        }
        quit()
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
    func quit() {
        _exit(EXIT_SUCCESS)
    }
}
