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
    /// The files that stayed after the app itself moved to the Trash. Peel is running from the Trash by then,
    /// so the alert that lists them has a single button, which quits.
    private(set) var leftBehind: String?

    static var removeCommand: String {
        "sudo rm -f /usr/local/bin/peel"
    }

    /// True only when `/usr/local/bin/peel` is Peel's own tool. For another program's `peel`, `removeCommand`
    /// would delete a file that is not Peel's.
    var hasCommandLineTool: Bool {
        CommandLineTool.standing(embedded: Bundle.main.bundleURL.appending(path: "Contents/Helpers/peel")) == .installed
    }

    /// Removes Peel. The plan is made first, and the steps nothing can undo (unregistering the helper and the
    /// login item) come after, so a plan that cannot be made leaves Peel as it was. A quit is refused meanwhile,
    /// since Peel ends itself once it has gone.
    func run(installedApps: [InstalledApp], helper: HelperModel, recording record: (TrashResult) async -> Void = { _ in }) async {
        isRunning = true
        defer { isRunning = false }
        await QuitGuard.shared.runRefusingQuit {
            await remove(installedApps: installedApps, helper: helper, recording: record)
        }
    }

    private func remove(installedApps: [InstalledApp], helper: HelperModel, recording record: (TrashResult) async -> Void) async {
        let bundleURL = Bundle.main.bundleURL
        guard let app = await AppLibrary.inspect(bundleURL) else {
            failure = String(localized: "Peel couldn’t read its own files.")
            return
        }
        let exclusions = ExclusionsStore.shared.exclusions
        let urls = await Uninstallation.prepare(app, installedApps: installedApps, exclusions: exclusions).unreviewedSelection
        guard !urls.isEmpty else {
            failure = String(localized: "Peel won’t move itself from here: its folder needs an administrator, or Peel is excluded in Settings. Drag it to the Trash in Finder, which asks for an administrator when one is needed.")
            return
        }

        let isRegistered = { [helper] in helper.status == .enabled || helper.status == .requiresApproval }
        var ledgerStayed: TrashFailure?
        if isRegistered() {
            ledgerStayed = await PrivilegedHelper.moveLedgerToTrash()
            await helper.uninstall()
            // A helper still registered would point into the Trash, so Peel moves only once the helper is gone.
            guard !isRegistered() else {
                failure = helper.failure?.reason ?? String(localized: "The helper couldn’t be removed, so Peel stayed where it was.")
                return
            }
        }
        try? await SMAppService.mainApp.unregister()

        let result = await SelfRemoval.move(urls, app: bundleURL, folder: PeelFolder.url, using: TrashService(exclusions: exclusions), recording: record)
        guard result.trashed.contains(where: { $0.originalURL == bundleURL }) else {
            failure = result.failures.map { "\($0.url.abbreviatedPath)\n\($0.reason.explanation)" }.joined(separator: "\n\n")
            return
        }
        let stayed = result.failures + [ledgerStayed].compactMap(\.self)
        guard stayed.isEmpty else {
            leftBehind = stayed.map { "\($0.url.abbreviatedPath)\n\($0.reason.explanation)" }.joined(separator: "\n\n")
            return
        }
        quit()
    }

    /// Exits at once rather than through `NSApp.terminate`, which would let AppKit write the window's frame
    /// and saved state again, both of which were just removed.
    func quit() {
        exit(0)
    }
}
