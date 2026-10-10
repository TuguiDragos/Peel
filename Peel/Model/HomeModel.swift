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
            case .helper: "Some leftovers sit in folders only an administrator can change. The helper moves those for Peel. macOS asks you to approve it once, in Login Items & Extensions. It belongs to the copy of Peel that installed it: a second copy, in another folder, has to install its own."
            case .appManagement: "macOS stops an app from moving another developer’s app to the Trash unless you allow it. Without this, Peel can still clear an app’s files, but macOS may refuse to move the app itself."
            case .notifications: "Tells you when your apps have new updates. With “Watch the Trash” on in Settings, it also tells you when you move an app to the Trash yourself, so you can clear what it left behind. With “Warn when the disk is almost full” on, it tells you that too."
            case .finderExtension: "Adds Uninstall with Peel to the menu you get when you Control-click an app in Finder."
            case .openAtLogin: "Starts Peel when you log in. “Watch the Trash” works only while Peel is running."
            case .commandLine: "Lets you uninstall apps and clear leftovers, caches, and duplicates from Terminal. Copy the install command and run it in Terminal: it asks for your password."
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

    private static let appManagementKey = "appManagementState"
    private static let modelNameKey = "modelName."

    let helper: HelperModel
    private(set) var device: DeviceInfo?
    /// The Finder extension is on, but macOS runs the one inside another copy of Peel, so this copy reads it as off.
    private(set) var isFinderExtensionFromAnotherCopy = false
    private let refreshes = OneRunAtATime()
    private var isReadingModelName = false
    private(set) var greeting = Greeting.at(.now)
    private var found: [Permission: State] = [:]
    private(set) var notificationStatus: UNAuthorizationStatus = .notDetermined
    private(set) var appManagement: AccessState = .unknown
    /// The App Management state a removal revealed since Peel opened. That answer came from macOS itself,
    /// weighing everything, including the signature the permission was given to, so it outranks the privacy
    /// database.
    private var appManagementSeenThisLaunch: AccessState?
    /// Full Disk Access only applies to a new process, so Peel offers to reopen itself.
    private(set) var needsRelaunchForFullDiskAccess = false
    /// Peel could not open a fresh copy of itself, so it stayed.
    var couldNotRelaunch = false
    /// False until the first check finishes. Until then no state is shown, so the panel never flashes a wrong one. The
    /// helper's row is checked apart and says so until its own answer.
    private(set) var hasChecked = false
    private var hasOpenedFullDiskAccessSettings = false

    init(helper: HelperModel) {
        self.helper = helper
        appManagement = AccessState(stored: UserDefaults.standard.string(forKey: Self.appManagementKey))
    }

    /// What each row shows. The helper's row is the helper model's, as it changes, from Home's first read on.
    var states: [Permission: State] {
        var states = found
        if hasChecked {
            states[.helper] = helperState
        }
        return states
    }

    var missingRequired: [Permission] {
        Permission.allCases.filter { $0.isRequired && state(of: $0).isMissing }
    }

    var needsAttention: Bool { !missingRequired.isEmpty }

    /// Required permissions still pending, such as a helper waiting for approval or a check that got no
    /// answer. Home doesn't say "You're all set" while any remain. App Management is left out: it is often
    /// known only after the first removal.
    var waitingRequired: [Permission] {
        Permission.allCases.filter { $0.isRequired && state(of: $0) == .pending && $0 != .appManagement }
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
        greeting = .at(.now)
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
        let isFinderExtensionEnabled = await Self.isFinderExtensionEnabled()
        isFinderExtensionFromAnotherCopy =
            isFinderExtensionEnabled ? false : await Self.finderExtensionRunsFromAnotherCopy()

        let fullDisk = await access
        needsRelaunchForFullDiskAccess = fullDisk == .missing && hasOpenedFullDiskAccessSettings
        let opensAtLogin = await Self.opensAtLogin()
        found = [
            .fullDiskAccess: state(for: fullDisk),
            .appManagement: state(for: appManagementSeenThisLaunch ?? appManagement),
            .notifications: notificationStatus == .authorized ? .on : .off,
            .finderExtension: isFinderExtensionEnabled ? .on : .off,
            .openAtLogin: opensAtLogin ? .on : .off,
            .commandLine: CommandLineTool.isOnThePath(embedded: Bundle.main.bundleURL.appending(path: "Contents/Helpers/peel")) ? .on : .off,
        ]
        hasChecked = true

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
        return UserDefaults.standard.string(forKey: Self.modelNameKey + identifier)
    }

    /// Reads the marketing name with `system_profiler` and saves it, when none is saved for this model yet.
    private func readModelName() async {
        guard !isReadingModelName, let identifier = device?.modelIdentifier, !identifier.isEmpty, modelName == nil
        else { return }
        isReadingModelName = true
        defer { isReadingModelName = false }
        guard let name = await DeviceInfo.marketingName() else { return }
        UserDefaults.standard.set(name, forKey: Self.modelNameKey + identifier)
        device = device?.named(name)
    }

    func updateGreeting() {
        greeting = .at(.now)
    }

    func record(appManagement state: AccessState) {
        appManagementSeenThisLaunch = state
        guard state != appManagement else { return }
        appManagement = state
        UserDefaults.standard.set(state.stored, forKey: Self.appManagementKey)
        found[.appManagement] = self.state(for: state)
    }

    func openFullDiskAccessSettings() {
        hasOpenedFullDiskAccessSettings = true
        NSWorkspace.shared.open(FullDiskAccess.settingsURL)
    }

    /// Opens the App Management settings and forgets the stored state. macOS has no API for this permission, so a
    /// stored "off" that only a removal updates would keep Home red after the user turns it on.
    func openAppManagementSettings() {
        appManagementSeenThisLaunch = nil
        appManagement = .unknown
        UserDefaults.standard.removeObject(forKey: Self.appManagementKey)
        found[.appManagement] = state(for: .unknown)
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
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert])
        notificationStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        found[.notifications] = notificationStatus == .authorized ? .on : .off
    }

    func openFinderExtensionSettings() {
        FIFinderSyncController.showExtensionManagementInterface()
    }

    /// Off the main thread: it waits for another process to answer.
    @concurrent
    private static func isFinderExtensionEnabled() async -> Bool {
        FIFinderSyncController.isExtensionEnabled
    }

    /// Off the main thread: `SMAppService` asks `smd` over XPC.
    @concurrent
    private static func opensAtLogin() async -> Bool {
        SMAppService.mainApp.status == .enabled
    }

    private static func finderExtensionRunsFromAnotherCopy() async -> Bool {
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
        CommandLineTool.standing(embedded: Bundle.main.bundleURL.appending(path: "Contents/Helpers/peel"))
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
