import AppKit
import FinderSync
import Foundation
import Observation
import PeelCore
import ServiceManagement
import UserNotifications

@Observable
final class HomeModel {
    enum Permission: String, CaseIterable, Identifiable {
        case fullDiskAccess
        case helper
        case appManagement
        case notifications
        case finderExtension
        case openAtLogin
        case commandLine

        var id: String { rawValue }

        var isRequired: Bool {
            switch self {
            case .fullDiskAccess, .helper, .appManagement: true
            case .notifications, .finderExtension, .openAtLogin, .commandLine: false
            }
        }

        /// What Home asks in System Settings of the permissions still waiting there. macOS lists the helper under Login
        /// Items & Extensions as Peel itself, so it is never named by its title.
        struct Waiting: Equatable {
            let allowsPeel: Bool
            let others: [Permission]
        }

        static func inSystemSettings(_ waiting: [Permission]) -> Waiting {
            Waiting(allowsPeel: waiting.contains(.helper), others: waiting.filter { $0 != .helper })
        }

        var title: LocalizedStringResource {
            switch self {
            case .fullDiskAccess: "Full Disk Access"
            case .helper: "Helper"
            case .appManagement: "App Management"
            case .notifications: "Notifications"
            case .finderExtension: "Finder Extension"
            case .openAtLogin: "Open at Login"
            case .commandLine: "Command Line"
            }
        }

        var detail: LocalizedStringResource {
            switch self {
            case .fullDiskAccess: "Lets Peel look inside the Trash and the private folders where apps keep their data. Without it, Peel can’t find everything an app leaves behind."
            case .helper: "Some leftovers sit in folders only an administrator can change. The helper moves those for Peel. macOS asks you to approve it once, in Login Items & Extensions. It belongs to the copy of Peel that installed it."
            case .appManagement: "macOS stops an app from moving another developer’s app to the Trash unless you allow it. Without this, Peel can still clear an app’s files, but macOS may refuse to move the app itself."
            case .notifications: "Tells you when your apps have new updates and when a Homebrew upgrade finishes or runs into a problem. With “Watch the Trash” on in Settings, it also tells you when you move an app to the Trash yourself, so you can clear what it left behind. With “Warn when the disk is almost full” on, it tells you that too."
            case .finderExtension: "Adds Uninstall with Peel to the menu you get when you Control-click an app in Finder."
            case .openAtLogin: "Starts Peel when you log in. “Watch the Trash” works only while Peel is running."
            case .commandLine: "Lets you uninstall apps and clear leftovers, caches, and duplicates from Terminal."
            }
        }

        var symbol: String {
            switch self {
            case .fullDiskAccess: "internaldrive"
            case .helper: "lock.shield"
            case .appManagement: "square.grid.2x2"
            case .notifications: "bell.badge"
            case .finderExtension: "cursorarrow.click.2"
            case .openAtLogin: "power"
            case .commandLine: "terminal"
            }
        }
    }

    enum State: Hashable {
        case on
        case off
        case missing
        case pending
        /// Only an administrator account can use it, so this account has nothing to set up here.
        case notThisAccount
        /// The helper's row until the helper is first checked, which can take the whole of the check's wait.
        case checking

        var isMissing: Bool { self == .missing }
    }

    /// The install command runs `sudo`, which only an administrator can use, so a standard account has nothing to run.
    static func commandLineState(isOnThePath: Bool, isAdministrator: Bool) -> State {
        isOnThePath ? .on : isAdministrator ? .off : .notThisAccount
    }

    private static let appManagementKey = "appManagementState"
    private static let modelNameKey = "modelName."

    let helper: HelperModel
    private(set) var device: DeviceInfo?
    /// The Finder extension is on, but macOS runs the one inside another copy of Peel, so this copy reads it as off.
    private(set) var isFinderExtensionFromAnotherCopy = false
    private let refreshes = OneRunAtATime()
    private var found: [Permission: State] = [:]
    private(set) var notificationStatus: UNAuthorizationStatus = .notDetermined
    private(set) var appManagement: AccessState = .unknown
    /// The App Management state a removal revealed since Peel opened. That answer came from macOS itself,
    /// weighing everything, including the signature the permission was given to, so it outranks the privacy
    /// database.
    private var appManagementSeenThisLaunch: AccessState?
    /// macOS refused this permission at a removal and the person has had the chance to change it since. macOS has no
    /// API for it, so only the next removal can say.
    private(set) var appManagementAwaitsARemoval = false
    /// How many times System Settings had come forward when macOS refused, while the refusal stands.
    private var systemSettingsShowsAtRefusal: Int?
    /// Full Disk Access only applies to a new process, so Peel offers to reopen itself.
    private(set) var needsRelaunchForFullDiskAccess = false
    /// Peel could not open a fresh copy of itself, so it stayed.
    var couldNotRelaunch = false
    /// False until the first check finishes. Until then no state is shown, so the panel never flashes a wrong one. The
    /// helper's row is checked apart and says so until its own answer.
    private(set) var hasChecked = false
    private let frontmost: FrontmostApp
    private let defaults: UserDefaults
    private let readsFinderExtension: FinderExtensionReads
    private let readsModelName: @Sendable () async -> String?
    private var hasAskedForTheModelName = false
    typealias FinderExtensionReads = (
        isEnabled: @Sendable () async -> Bool, runsFromAnotherCopy: @Sendable () async -> Bool
    )

    /// The login item Settings switches too, so Home shows each change as it lands.
    let loginItem: LoginItem

    init(
        helper: HelperModel,
        loginItem: LoginItem = .ofTheMainApp(),
        defaults: UserDefaults = .standard,
        frontmost: FrontmostApp = .shared,
        readsFinderExtension: FinderExtensionReads = (
            isEnabled: { await isFinderExtensionEnabled() },
            runsFromAnotherCopy: { await finderExtensionRunsFromAnotherCopy() }
        ),
        readsModelName: @escaping @Sendable () async -> String? = { await DeviceInfo.marketingName() }
    ) {
        self.helper = helper
        self.loginItem = loginItem
        self.defaults = defaults
        self.frontmost = frontmost
        self.readsFinderExtension = readsFinderExtension
        self.readsModelName = readsModelName
        let stored = AccessState(stored: defaults.string(forKey: Self.appManagementKey))
        appManagementAwaitsARemoval = stored == .missing
        appManagement = stored == .missing ? .unknown : stored
    }

    /// What each row shows. The helper's row is the helper model's, as it changes, from Home's first read on.
    var states: [Permission: State] {
        var states = found
        if hasChecked {
            states[.helper] = helperState
        }
        if let status = loginItem.status {
            states[.openAtLogin] = status == .enabled ? .on : .off
        }
        return states
    }

    var missingRequired: [Permission] {
        Permission.allCases.filter { $0.isRequired && state(of: $0).isMissing }
    }

    var needsAttention: Bool { !missingRequired.isEmpty }

    /// What the Command Line row's note says to do, which is what its button offers and what Settings says. Nil once
    /// the tool is on the path.
    static func commandLineNextStep(
        state: State, standing: CommandLineTool.Standing, place: CommandLineTool.Place
    ) -> LocalizedStringResource? {
        guard state != .on else { return nil }
        switch place {
        case .temporaryCopy:
            return "Peel is running from a copy macOS made because it is still marked as downloaded. Move Peel to the Applications folder and open it from there."
        case .readOnlyVolume:
            return "Peel is running from a read-only disk, such as the disk image it came on. Move Peel to the Applications folder and open it from there."
        case .applications, .elsewhere:
            break
        }
        if state == .notThisAccount {
            return "Putting it on the path takes an administrator, and Peel’s Settings gives a line for your shell that runs it from this account."
        }
        if standing == .somethingElse {
            return "Something else is at \(CommandLineTool.path), and Peel offers no command that would replace it."
        }
        return "Copy the install command and run it in Terminal: it asks for your password."
    }

    /// Required permissions still pending, such as a helper waiting for approval or a check that got no
    /// answer. Home doesn't say "You're all set" while any remain. App Management counts only after a refusal: it is
    /// often known only after the first removal.
    var waitingRequired: [Permission] {
        Permission.allCases.filter {
            $0.isRequired && state(of: $0) == .pending && ($0 != .appManagement || appManagementAwaitsARemoval)
        }
    }

    func state(of permission: Permission) -> State {
        states[permission] ?? .pending
    }

    var isStillChecking: Bool {
        states.values.contains(.checking)
    }

    /// Reads again what Home shows: the Mac's details and the state of every permission. One call runs at a
    /// time, since two overlapping calls would both find nothing read yet, and a call made meanwhile, such as the
    /// one when Peel comes forward, runs once more when it ends.
    func refresh() async {
        await refreshes.run { await read() }
        // The model's marketing name is the only slow part (a `system_profiler` process), so it is read outside
        // the runs, which it would otherwise hold up.
        await readModelName()
    }

    private func read() async {
        // The card needs none of the checks below, so it is read first and arrives with the window.
        let isFirstRead = device == nil
        if isFirstRead {
            device = await DeviceInfo.withoutTheModelName()
            // `modelName` reads the identifier off `device`.
            if let known = modelName {
                device = device?.named(known)
            }
        }
        async let access = FullDiskAccess.state()
        async let helperChecked: Void = helper.checkConnection()

        notificationStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        let isFinderExtensionEnabled = await readsFinderExtension.isEnabled()

        let fullDisk = await access
        needsRelaunchForFullDiskAccess = FullDiskAccess.offersReopen(
            fullDisk, systemSettingsWasInFront: frontmost.hasShownSystemSettings
        )
        await loginItem.refresh()
        followSystemSettings()
        found = [
            .fullDiskAccess: state(for: fullDisk),
            .appManagement: state(for: appManagementSeenThisLaunch ?? appManagement),
            .notifications: notificationStatus == .authorized ? .on : .off,
            .finderExtension: isFinderExtensionEnabled ? .on : .off,
            .commandLine: Self.commandLineState(
                isOnThePath: CommandLineTool.isOnThePath(
                    embedded: Bundle.main.bundleURL.appending(path: "Contents/Helpers/peel")
                ),
                isAdministrator: helper.isAvailableToThisAccount
            ),
        ]
        hasChecked = true

        // Only a word of an optional row hangs on this, and `pluginkit` can take seconds, so no row waits for it.
        isFinderExtensionFromAnotherCopy = isFinderExtensionEnabled
            ? false : await readsFinderExtension.runsFromAnotherCopy()
        await helperChecked

        // Free space is read every time, since it is how the user sees that a cleanup worked.
        if !isFirstRead, let device {
            self.device = await device.withStorageRead().named(modelName)
        }
    }

    /// The saved marketing name of the Mac's model. A model never changes, so the name is read once and kept,
    /// under the model identifier so a disk moved to another Mac doesn't bring the wrong name.
    private var modelName: String? {
        let identifier = device?.modelIdentifier ?? ""
        guard !identifier.isEmpty else { return nil }
        return defaults.string(forKey: Self.modelNameKey + identifier)
    }

    /// Reads the marketing name with `system_profiler` and saves it, when none is saved for this model yet. It is asked
    /// once a launch: a `system_profiler` that didn't answer would otherwise take seconds each time Peel comes forward.
    private func readModelName() async {
        guard !hasAskedForTheModelName, let identifier = device?.modelIdentifier, !identifier.isEmpty, modelName == nil
        else { return }
        hasAskedForTheModelName = true
        guard let name = await readsModelName() else { return }
        defaults.set(name, forKey: Self.modelNameKey + identifier)
        device = device?.named(name)
    }

    func record(appManagement state: AccessState) {
        appManagementSeenThisLaunch = state
        appManagementAwaitsARemoval = false
        systemSettingsShowsAtRefusal = state == .missing ? frontmost.systemSettingsShows : nil
        guard state != appManagement else { return }
        appManagement = state
        defaults.set(state.stored, forKey: Self.appManagementKey)
        found[.appManagement] = self.state(for: state)
    }

    func openFullDiskAccessSettings() {
        NSWorkspace.shared.open(FullDiskAccess.settingsURL)
    }

    /// A refusal stands until System Settings has come forward, by whichever button or by hand: only a removal updates
    /// it, so it would keep Home red after the person turned the permission on.
    func followSystemSettings() {
        guard let shows = systemSettingsShowsAtRefusal, frontmost.systemSettingsShows > shows else { return }
        systemSettingsShowsAtRefusal = nil
        appManagementSeenThisLaunch = nil
        appManagement = .unknown
        appManagementAwaitsARemoval = true
        found[.appManagement] = .pending
    }

    /// Opens the App Management settings, where the person can turn off what a removal found on, so that answer no
    /// longer holds.
    func openAppManagementSettings() {
        if (appManagementSeenThisLaunch ?? appManagement) == .granted {
            appManagementSeenThisLaunch = nil
            appManagement = .unknown
            defaults.removeObject(forKey: Self.appManagementKey)
            found[.appManagement] = state(for: .unknown)
        }
        NSWorkspace.shared.open(AppManagement.settingsURL)
    }

    func openAboutThisMac() {
        NSWorkspace.shared.open(DeviceInfo.aboutURL)
    }

    func openLoginItemsSettings() {
        PrivilegedHelper.openLoginItemsSettings()
    }

    func openNotificationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") else { return }
        NSWorkspace.shared.open(url)
    }

    func requestNotifications() async {
        guard notificationStatus == .notDetermined else {
            openNotificationSettings()
            return
        }
        await PeelNotifications.requestAuthorization()
        // Through `refresh`, so a read already running reads again rather than showing what it found before.
        await refresh()
    }

    func openFinderExtensionSettings() {
        FIFinderSyncController.showExtensionManagementInterface()
    }

    /// Off the main thread: it waits for another process to answer.
    @concurrent
    private nonisolated static func isFinderExtensionEnabled() async -> Bool {
        FIFinderSyncController.isExtensionEnabled
    }

    private nonisolated static func finderExtensionRunsFromAnotherCopy() async -> Bool {
        guard let own = Bundle.main.builtInPlugInsURL.flatMap({ Bundle(url: $0.appending(path: "PeelFinder.appex")) }),
              let identifier = own.bundleIdentifier
        else { return false }
        return await AppExtensions.runsAnotherCopy(of: identifier, than: own.bundleURL)
    }

    /// Full Disk Access reaches Peel only after it quits, so this opens a new copy and quits this one. It quits
    /// only once the new copy is open, so the user is never left without Peel.
    func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            Task { @MainActor in
                guard error == nil else {
                    self.couldNotRelaunch = true
                    return
                }
                QuitGuard.quit()
            }
        }
    }

    /// The helper serves administrator accounts only, so on a standard account it is not missing: there is
    /// nothing for this account to install.
    private var helperState: State {
        guard helper.hasChecked else { return .checking }
        return switch helper.standing {
        case .ready: .on
        case .waitingForApproval: .pending
        case .notInstalled, .notAnswering: .missing
        case .notThisAccount: .notThisAccount
        }
    }

    private func state(for access: AccessState) -> State {
        switch access {
        case .granted: .on
        case .missing: .missing
        case .unknown: .pending
        }
    }

    static var commandLineStanding: CommandLineTool.Standing {
        CommandLineTool.standingOnThePath(embedded: Bundle.main.bundleURL.appending(path: "Contents/Helpers/peel"))
    }
}

extension AccessState {
    init(stored: String?) {
        switch stored {
        case "granted": self = .granted
        case "missing": self = .missing
        default: self = .unknown
        }
    }

    var stored: String {
        switch self {
        case .granted: "granted"
        case .missing: "missing"
        case .unknown: "unknown"
        }
    }
}
