import Foundation
import PeelCore
import Sparkle

/// Peel's own updates, through Sparkle: it reads the signed feed, shows the new version to the person, and installs it
/// only when they choose, once the update's signature checks out. What Sparkle may do is set in the Info.plist.
///
/// A new version found while the person works is told gently, by the face, the sidebar and About, and Sparkle's window
/// opens when they ask for it; Sparkle shows it at once only when it would have their full attention anyway.
@Observable
final class PeelUpdater: NSObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    /// The version Sparkle last found newer than this copy, nil until it finds one and once it finds none.
    private(set) var newerVersion: String?
    private(set) var canCheckForUpdates = false
    @ObservationIgnored private var controller: SPUStandardUpdaterController?
    @ObservationIgnored private var canCheck: NSKeyValueObservation?

    #if DEBUG
    /// About as it reads once Sparkle found `version`, for `HomeSnapshot`.
    convenience init(found version: String) {
        self.init()
        newerVersion = version
    }
    #endif

    func start() {
        guard controller == nil else { return }
        // Sparkle asks through a session that keeps cookies, and GitHub sets one that would come back with every later
        // check, linking them all to this Mac. Peel takes no cookies and forgets any it was given.
        HTTPCookieStorage.shared.cookieAcceptPolicy = .never
        HTTPCookieStorage.shared.removeCookies(since: .distantPast)
        let controller = SPUStandardUpdaterController(
            startingUpdater: false, updaterDelegate: self, userDriverDelegate: self
        )
        self.controller = controller
        // Peel's own update checks tell a server no more than this either.
        controller.updater.userAgentString = "Peel"
        controller.updater.httpHeaders = ["Accept-Language": "*"]
        let options: NSKeyValueObservingOptions = [.initial, .new]
        canCheck = controller.updater.observe(\.canCheckForUpdates, options: options) { [weak self] updater, _ in
            MainActor.assumeIsolated { self?.canCheckForUpdates = updater.canCheckForUpdates }
        }
        controller.startUpdater()
    }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }

    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        let checksForAppUpdates = UserDefaults.standard.isOn(SettingsKey.checksForAppUpdates, whenNeverSet: true)
        guard OwnUpdateCheck.mayAsk(askedByThePerson: updateCheck == .updates, checksForAppUpdates: checksForAppUpdates)
        else { throw UpdateChecksAreOff() }
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        newerVersion = item.displayVersionString
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
        newerVersion = nil
    }

    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        immediateFocus
    }
}

/// Why Sparkle skips a check it starts on its own, in its log. It shows nothing and schedules the next check.
private struct UpdateChecksAreOff: LocalizedError {
    var errorDescription: String? { "Check for app updates is off." }
}
