import AppKit
import Foundation
import Observation
import PeelCore

@Observable
final class ResetPlan {
    let app: InstalledApp
    private(set) var reset: AppReset?
    /// The scan the sheet runs. A new scan, such as the one after the exclusions change, replaces the one before.
    let scanRun = ScanRun()
    private(set) var isResetting = false
    private(set) var backup: URL?
    private(set) var failures: [TrashFailure] = []
    private(set) var didReset = false
    /// True when the settings could not be backed up, so nothing was moved. The backup is what restores them
    /// once the app has written new ones, which History cannot do.
    private(set) var couldNotSaveSettings = false
    private(set) var movedCount = 0
    /// How many files the reset asked to move: a reset of privacy permissions alone asks for none.
    private(set) var askedToMove = 0
    private(set) var didClearSettings = false
    /// Off until chosen: History can't bring the permissions back.
    var resetsPrivacy = false
    private(set) var privacy: PrivacyReset.Result?
    /// Stored rather than computed, so the sheet can observe it: reading the workspace in a computed property
    /// gives Observation nothing to track. `refreshRunningState()` keeps it current.
    private(set) var isAppRunning = false
    /// Every installed app as of the last scan. It tells this app's running helpers apart from another app's.
    private var installedApps: [InstalledApp] = []
    var selectedURLs: Set<URL> = []
    private var choices = KeptSelection()

    init(app: InstalledApp) {
        self.app = app
        refreshRunningState()
    }

    var items: [AppReset.Item] {
        reset?.items ?? []
    }

    func items(in group: AppReset.Group) -> [AppReset.Item] {
        reset?.items(in: group) ?? []
    }

    var selected: SizeTotal {
        reset?.size(of: selectedURLs) ?? SizeTotal(known: 0, isComplete: true)
    }

    var keepsAppData: Bool {
        reset?.keepsAppData ?? false
    }

    var needsFullDiskAccess: Bool {
        reset?.needsFullDiskAccess ?? false
    }

    var canResetPrivacy: Bool {
        PrivacyReset.isAllowed(bundleIdentifier: app.bundleIdentifier)
    }

    var hasAnythingToReset: Bool {
        !selectedURLs.isEmpty || (resetsPrivacy && canResetPrivacy)
    }

    /// Updates `isAppRunning`. Called when the sheet opens and whenever an app launches or quits.
    func refreshRunningState() {
        isAppRunning = !relatedRunningApps.isEmpty
    }

    func refresh(installedApps: [InstalledApp]) async {
        let app = app
        guard let result = await scanRun.run({
            await AppReset.prepare(app, installedApps: installedApps, exclusions: ExclusionsStore.shared.exclusions)
        }) else { return }
        selectedURLs = choices.update(selectedURLs, selectable: Set(result.items.map(\.url)), suggested: result.suggestedSelection)
        reset = result
        self.installedApps = installedApps
        refreshRunningState()
    }

    /// Backs up the app's settings, then moves the selection to the Trash, which also makes cfprefsd forget the
    /// app's preference domains. Checks that the app is not running before the copy and again before the move,
    /// since the copy takes a moment: an app opened meanwhile would have its files moved from under it, and would
    /// write its settings back when it quits. Then nothing moves, and the copy stays.
    func performReset() async -> TrashResult {
        refreshRunningState()
        guard let reset, !isAppRunning else { return TrashResult() }
        isResetting = true
        defer { isResetting = false }

        let urls = reset.selected(selectedURLs)
        switch await PreferenceBackup.save(urls, for: app, exclusions: ExclusionsStore.shared.exclusions) {
        case .failed:
            couldNotSaveSettings = true
            return TrashResult()
        case .saved(let folder):
            backup = folder
        case .nothingToSave:
            backup = nil
        }
        couldNotSaveSettings = false
        refreshRunningState()
        guard !isAppRunning else { return TrashResult() }
        let result = await TrashService(exclusions: ExclusionsStore.shared.exclusions).trash(urls, ownedBy: app.bundleIdentifier)
        failures = result.failures
        movedCount = result.trashed.count
        askedToMove = urls.count
        didClearSettings = reset.clearsSettings(moving: result.trashed.map(\.originalURL))
        // The app stays installed, so `tccutil` still finds it after the move.
        privacy = resetsPrivacy && canResetPrivacy ? await PrivacyReset.reset(bundleIdentifier: app.bundleIdentifier) : nil
        didReset = true
        return result
    }

    /// Puts the saved settings back. Refused while the app is running, since it would write its own settings
    /// over them.
    func putSettingsBack() async -> Bool {
        refreshRunningState()
        guard let backup, !isAppRunning else { return false }
        return await QuitGuard.shared.run {
            await PreferenceBackup.restore(from: backup, of: app.bundleIdentifier, exclusions: ExclusionsStore.shared.exclusions)
        }.isComplete
    }

    /// Quits the app and the helpers it ships, so nothing writes its settings again while they are cleared.
    func quitApp() {
        for running in relatedRunningApps {
            running.terminate()
        }
    }

    private var relatedRunningApps: [NSRunningApplication] {
        RunningCopies.belonging(to: app, among: RunningCopies.current, installedApps: installedApps, sharingItsSettings: true)
            .compactMap { NSRunningApplication(processIdentifier: $0.identifier) }
    }
}

extension AppReset.Group {
    var title: LocalizedStringResource {
        switch self {
        case .settings: "Settings"
        case .webData: "Cookies and Website Data"
        case .appData: "What the App Keeps for You"
        }
    }

    var explanation: LocalizedStringResource {
        switch self {
        case .settings: "The app writes all of this again the next time it opens. An app may also keep what it remembers about you here, such as a license key or an account you stayed signed in to, and then those go too."
        case .webData: "Removing this signs you out of websites the app kept you signed in to."
        case .appData: "This is what the app keeps for you, which can include your own work. Peel never selects it for you."
        }
    }
}
