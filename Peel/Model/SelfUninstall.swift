import AppKit
import Foundation
import Observation
import PeelCore
import ServiceManagement

/// Peel removing itself: its own files and the app, once the helper and the login item are gone.
@Observable
final class SelfUninstall {
    private(set) var isRunning = false
    var failure: String?
    /// What stayed after the app itself moved to the Trash: files, and a login item. Peel is running from the Trash by
    /// then, so the alert that lists them has a single button, which quits.
    private(set) var leftBehind: String?

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

    /// Removes Peel. The plan is made first, and the steps nothing can undo (unregistering the helper and the
    /// login item) come after, so a plan that cannot be made leaves Peel as it was. A quit is refused meanwhile,
    /// since Peel ends itself once it has gone. `work` is paused from the first of those steps, since what it does
    /// on its own would write Peel's files again, and resumed if Peel stays where it was.
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

        work.pause()
        let isRegistered = { [helper] in helper.status == .enabled || helper.status == .requiresApproval }
        var ledger = PrivilegedHelper.LedgerMove.none
        var links = TrashResult()
        if isRegistered() {
            if helper.status == .enabled {
                let own = plan.unreviewedLinks
                links = await TrashService(exclusions: exclusions).trash(own, usingHelperFor: Set(own))
            }
            ledger = await PrivilegedHelper.moveLedgerToTrash()
            let helperFailure = await helper.uninstall()
            // A helper still registered would point into the Trash, so Peel moves only once the helper is gone.
            guard !isRegistered() else {
                work.resume()
                if !links.trashed.isEmpty {
                    await record(TrashResult(trashed: links.trashed))
                }
                let reason = helperFailure?.reason ?? String(localized: "The helper couldn’t be removed, so Peel stayed where it was.")
                failure = ledger == .moved ? "\(reason)\n\n\(Self.ledgerInTheTrash)" : reason
                return
            }
        }
        // Unregistering a login item that was never registered fails too, so what counts is whether it is still there.
        try? await SMAppService.mainApp.unregister()
        let opensAtLogin = [.enabled, .requiresApproval].contains(SMAppService.mainApp.status)

        let result = await SelfRemoval.move(
            urls,
            app: bundleURL,
            folder: PeelFolder.url,
            movedFirst: links.trashed,
            using: TrashService(exclusions: exclusions),
            recording: record
        )
        guard result.trashed.contains(where: { $0.originalURL == bundleURL }) else {
            work.resume()
            let lines = result.failures.map { "\($0.url.abbreviatedPath)\n\($0.reason.explanation)" }
            failure = (lines + (ledger == .moved ? [Self.ledgerInTheTrash] : [])).joined(separator: "\n\n")
            return
        }
        _ = await DockTiles().takeOut([bundleURL], remembering: false)
        var stayed = result.failures + links.failures
        if case .stayed(let failure) = ledger {
            stayed.append(failure)
        }
        var lines = stayed.map { "\($0.url.abbreviatedPath)\n\($0.reason.explanation)" }
        if opensAtLogin {
            lines.append(String(localized: "Peel is still set to open at login: remove it in System Settings > General > Login Items & Extensions."))
        }
        guard lines.isEmpty else {
            leftBehind = lines.joined(separator: "\n\n")
            return
        }
        quit()
    }

    /// Said when Peel stays after the helper's ledger went to the Trash: without it, the helper puts back nothing it
    /// moved, now or once it is installed again.
    private static var ledgerInTheTrash: String {
        let folder = PrivilegedHelper.ledgerFolder
        return String(localized: "Peel’s helper keeps a record of what it moves, and that record is already in the Trash, as \(folder.lastPathComponent). Until it is back in \(folder.deletingLastPathComponent().abbreviatedPath), History can’t put back what the helper moved.")
    }

    /// Exits at once rather than through `NSApp.terminate`, which would let AppKit write the window's frame
    /// and saved state again, both of which were just removed.
    func quit() {
        exit(0)
    }
}
