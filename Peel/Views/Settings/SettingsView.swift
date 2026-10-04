import AppKit
import FinderSync
import PeelCore
import ServiceManagement
import SwiftUI

/// The tabs of Settings. The one open is remembered under `SettingsKey.pane`, which is also how another page
/// opens Settings at a tab of its choosing.
enum SettingsPane: String {
    case general
    case exclusions
    case privacy
    case helper

    /// Opens Settings at this tab, where the action that sent the person there is.
    func open(with openSettings: OpenSettingsAction) {
        UserDefaults.standard.set(rawValue, forKey: SettingsKey.pane)
        openSettings()
    }
}

/// The Settings tabs, shared by the Settings window (Command-Comma) and the Settings page in Peel's sidebar.
/// The last open tab is remembered, as the Human Interface Guidelines ask of a settings window.
struct SettingsTabs: View {
    @AppStorage(SettingsKey.pane) private var pane = SettingsPane.general.rawValue
    /// Whether each tab is as tall as what it shows, which the Settings window follows. On the Settings page the
    /// tabs fill the column.
    var fitsEachTab = false

    var body: some View {
        TabView(selection: $pane) {
            Tab("General", systemImage: "gearshape", value: SettingsPane.general.rawValue) {
                fitted(GeneralSettingsView())
            }
            Tab("Exclusions", systemImage: "hand.raised", value: SettingsPane.exclusions.rawValue) {
                fitted(ExclusionsSettingsView())
            }
            Tab("Privacy", systemImage: "network", value: SettingsPane.privacy.rawValue) {
                fitted(PrivacySettingsView())
            }
            Tab("Helper", systemImage: "lock.shield", value: SettingsPane.helper.rawValue) {
                fitted(HelperSettingsView())
            }
        }
    }

    /// A tab as tall as what it shows, up to 520 points, past which it scrolls. A tab view gives every tab the
    /// same height unless each asks for its own, which is what `fixedSize` does here.
    @ViewBuilder
    private func fitted(_ tab: some View) -> some View {
        if fitsEachTab {
            tab
                .frame(width: 680)
                .frame(maxHeight: 520)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            tab
        }
    }
}

/// The Settings window's content. The `Settings` scene sizes the window to fit it, so the window takes the
/// height of the tab shown and can't be resized, as a settings window on the Mac does.
struct SettingsView: View {
    var body: some View {
        SettingsTabs(fitsEachTab: true)
    }
}

enum SettingsKey {
    static let pane = "settingsPane"
    static let checksForAppUpdates = "checksForAppUpdates"
    static let watchesTrash = "watchesTrash"
    static let warnsWhenDiskIsNearlyFull = "lowDiskSpace.warns"
    static let toldDiskIsNearlyFull = "lowDiskSpace.told"
    /// The tools the sidebar leaves out (`Tool.hidden(in:)`).
    static let hiddenTools = "sidebar.hiddenTools"
    /// The `peel` tool reads these three keys too, so they are defined once, in PeelCore.
    static let updateSource = UpdatePreferences.Key.source
    static let ignoredUpdateApps = UpdatePreferences.Key.ignoredApps
    static let skippedUpdateVersions = UpdatePreferences.Key.skippedVersions
    static let updateMemory = "updateMemory"

    /// Nil while something that may not be Peel's is where the link goes.
    static var commandLineInstallCommand: String? {
        CommandLineTool.installCommand(embedded: Bundle.main.bundleURL.appending(path: "Contents/Helpers/peel"), standing: HomeModel.commandLineStanding)
    }
}

/// A small capsule that shows a state, such as On or Not installed, with a tinted symbol. Settings keeps the
/// system's plain look here rather than Peel's sticker badges.
private func state(_ title: LocalizedStringResource, _ symbol: String, _ tint: Color) -> some View {
    HStack(spacing: 4) {
        Text(title)
        Image(systemName: symbol)
            .foregroundStyle(tint)
    }
    .font(.caption)
    .foregroundStyle(.secondary)
    .padding(.horizontal, 8)
    .padding(.vertical, 3)
    .background(.quaternary, in: .capsule)
}

private struct GeneralSettingsView: View {
    private var installCommand: String? { SettingsKey.commandLineInstallCommand }
    private static let place = CommandLineTool.place()

    @AppStorage(SettingsKey.checksForAppUpdates) private var checksForAppUpdates = true
    @AppStorage(SettingsKey.updateSource) private var updateSource = UpdateSource.automatic.rawValue
    @AppStorage(SettingsKey.watchesTrash) private var watchesTrash = false
    @AppStorage(SettingsKey.warnsWhenDiskIsNearlyFull) private var warnsWhenDiskIsNearlyFull = false
    @AppStorage(SettingsKey.hiddenTools) private var hiddenTools = ""
    @Environment(TrashMonitor.self) private var trashMonitor
    @Environment(AppLibrary.self) private var library
    @Environment(HomebrewLibrary.self) private var homebrew
    @Environment(HelperModel.self) private var helper
    @Environment(RemovalHistoryStore.self) private var history
    @Environment(StandingWork.self) private var background
    @Environment(HomeModel.self) private var home
    @State private var selfUninstall = SelfUninstall()
    @State private var isConfirmingSelfRemoval = false
    // The login item's state is read when the page appears (`readStandings()`), not as an initial value:
    // initial values run on every `init` of the view, and each read is a synchronous call to a daemon.
    @State private var opensAtLogin = false
    @State private var needsApprovalToOpenAtLogin = false
    @State private var loginItemFailure: String?

    /// Registers or unregisters Peel as a login item, then shows the status macOS reports. After `register()`,
    /// a login item the user turned off in Login Items still needs approval, so the toggle stays on and a note
    /// says why. An error is shown, not ignored.
    private func setOpensAtLogin(_ shouldOpen: Bool) {
        loginItemFailure = nil
        do {
            if shouldOpen {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            loginItemFailure = error.localizedDescription
        }
        let status = SMAppService.mainApp.status
        opensAtLogin = status == .enabled || status == .requiresApproval
        needsApprovalToOpenAtLogin = status == .requiresApproval
    }

    private func readStandings() {
        let status = SMAppService.mainApp.status
        opensAtLogin = status == .enabled || status == .requiresApproval
        needsApprovalToOpenAtLogin = status == .requiresApproval
    }

    var body: some View {
        Form {
            Section("Updates") {
                toggle("Check for app updates", isOn: $checksForAppUpdates,
                       "Peel asks each app’s update feed, the App Store, or Homebrew for the latest version. It never installs anything on its own.")
                // The choices stay short, because a pop-up button that doesn't fit truncates its title. The note
                // explains what Automatic does.
                LabeledContent {
                    Picker(selection: $updateSource) {
                        Text("Automatic").tag(UpdateSource.automatic.rawValue)
                        Text("The App Store").tag(UpdateSource.appStore.rawValue)
                        Text("The app’s own feed").tag(UpdateSource.developer.rawValue)
                        Text("Homebrew").tag(UpdateSource.homebrew.rawValue)
                    } label: {
                        EmptyView()
                    }
                    .labelsHidden()
                    .accessibilityLabel(Text("Prefer updates from"))
                } label: {
                    titled("Prefer updates from",
                           "Automatic asks Homebrew first about an app Homebrew installed, then the app’s own feed or the App Store. When the source you prefer can’t answer for an app, its own feed does.")
                }
                .disabled(!checksForAppUpdates)
                .onChange(of: updateSource) { _, _ in
                    Task { await library.updateSourceChanged() }
                }
            }

            if !muted.isEmpty {
                Section {
                    ForEach(muted) { item in
                        mutedRow(item)
                    }
                } header: {
                    titled("Muted Updates",
                           "Apps Peel stays quiet about, because you chose Never Check This App or skipped a version. Checking one again brings its updates back.")
                }
            }

            AppFoldersSection()

            HomebrewSection()

            Section("While Peel Runs") {
                toggle("Watch the Trash", isOn: $watchesTrash,
                       "When you move an app to the Trash yourself, Peel offers to remove the files it left behind. Peel stays in the menu bar to do it.")
                if watchesTrash, trashMonitor.status == .needsFullDiskAccess {
                    HStack {
                        WarningLabel(title: Text("Peel needs Full Disk Access to watch the Trash."), systemImage: "lock.trianglebadge.exclamationmark")
                        Spacer()
                        // Goes through `HomeModel`, so Home offers "Reopen Peel" afterward: Full Disk Access
                        // applies only to a process started after it is granted.
                        Button("Open System Settings") {
                            home.openFullDiskAccessSettings()
                        }
                    }
                } else if watchesTrash, trashMonitor.status == .off {
                    WarningLabel(title: Text("Peel isn’t watching the Trash right now. It tries again each time you come back to Peel."))
                }
                toggle("Warn when the disk is almost full", isOn: $warnsWhenDiskIsNearlyFull,
                       "When less than a tenth of the disk your home folder is on is available, Peel sends a notification that opens Space. It checks only while it is running.")
                // A binding, not `onChange`: setting `opensAtLogin` to macOS's answer must not register or
                // unregister again.
                toggle("Open Peel at login", isOn: Binding(get: { opensAtLogin }, set: setOpensAtLogin),
                       "Starts Peel when you log in. “Watch the Trash” works only while Peel is running.")
                if needsApprovalToOpenAtLogin {
                    HStack {
                        WarningLabel(title: Text("Peel is turned off in Login Items & Extensions, so macOS won’t start it."))
                        Spacer()
                        Button("Open System Settings") {
                            SMAppService.openSystemSettingsLoginItems()
                        }
                    }
                }
                if let loginItemFailure {
                    WarningLabel(title: Text(loginItemFailure))
                        .textSelection(.enabled)
                }
            }

            Section {
                // In the sidebar's own order.
                ForEach(Tool.Group.allCases.flatMap(\.tools).filter(\.canBeHidden)) { tool in
                    Toggle(isOn: showsInSidebar(tool)) {
                        Label { Text(tool.title) } icon: { Image(systemName: tool.systemImage) }
                    }
                }
            } header: {
                titled("Sidebar", "Turn a tool off to leave it out of the sidebar. The View menu and Shortcuts still open it.")
            }

            Section("Elsewhere on This Mac") {
                LabeledContent {
                    Button("Open System Settings") {
                        FIFinderSyncController.showExtensionManagementInterface()
                    }
                } label: {
                    // Uses `HomeModel`'s state, so Home and Settings can't show different answers.
                    let isOn = home.state(of: .finderExtension) == .on
                    HStack(spacing: 5) {
                        Text("Finder extension")
                        state(isOn ? "On" : home.isFinderExtensionFromAnotherCopy ? "On in another copy of Peel" : "Off",
                              isOn ? "checkmark.circle" : "minus.circle",
                              isOn ? .green : .secondary)
                        InfoNote(
                            name: String(localized: "Finder extension"),
                            detail: Text("Control-click an app in Finder and choose Uninstall with Peel to see what it leaves behind.")
                        )
                    }
                }
                LabeledContent {
                    // Not offered from a temporary copy: a link into it would break as soon as Peel quits.
                    if Self.place != .temporaryCopy, let installCommand {
                        CopyButton(text: installCommand)
                    }
                } label: {
                    titled("Command-line tool",
                           "Run the command in Terminal to use peel from anywhere, then type peel --help to see what it can do.")
                }
                switch Self.place {
                case .applications:
                    EmptyView()
                case .temporaryCopy:
                    Text("Peel is running from a copy macOS made because it is still marked as downloaded. Move Peel to the Applications folder and open it from there.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .elsewhere:
                    Text("The link points at Peel where it is now, \(Text(verbatim: Bundle.main.bundleURL.abbreviatedPath)), so it breaks if Peel moves. Apps live in the Applications folder.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if Self.place != .temporaryCopy {
                    if let installCommand {
                        Text(verbatim: installCommand)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    } else {
                        Text("Something else is at \(Text(verbatim: CommandLineTool.path)), and Peel offers no command that would replace it.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            SavedSettingsSection()

            Section {
                // Homebrew lists the copy it installed until `brew uninstall` removes it.
                if let cask = ownCask {
                    let command = "brew uninstall --zap --cask \(cask.name)"
                    LabeledContent {
                        CopyButton(text: command)
                    } label: {
                        titled("Remove Peel",
                               "Homebrew installed this copy of Peel, so remove it with Homebrew, or Homebrew goes on listing it as installed. Run the command in Terminal: Homebrew deletes the app rather than moving it to the Trash, and moves Peel’s files to the Trash, its folder in Application Support among them. That folder holds History, your exclusions, and Saved Settings.")
                    }
                    Text(verbatim: command)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                } else {
                    // The button is taller than a row, and `LabeledContent` would align the title with its top
                    // edge. An `HStack` centers the title and the button vertically.
                    HStack {
                        titled("Remove Peel",
                               "Peel removes its helper and login item, moves itself, the files that are certainly its own, and its folder in Application Support to the Trash, clears its settings, then quits. That folder holds History, your exclusions, and Saved Settings. The Finder extension goes with the app.")
                        Spacer(minLength: 8)
                        Button("Remove Peel", systemImage: "trash") {
                            isConfirmingSelfRemoval = true
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        // Disabled until the app list and Homebrew's have loaded: without the first, a file Peel
                        // shares with another app would look like Peel's alone, and without the second, a copy
                        // Homebrew installed would look like one it didn't.
                        .disabled(
                            selfUninstall.isRunning || !library.hasLoaded
                                || (homebrew.isInstalled && homebrew.packages == nil)
                        )
                    }
                }
                // Homebrew removes the links its cask made, and no other.
                if selfUninstall.hasCommandLineTool, ownCask?.commandLinks.contains(CommandLineTool.path) != true {
                    Text("Removing Peel leaves the peel command in place. To remove it too, run: \(Text(verbatim: SelfUninstall.removeCommand).font(.caption.monospaced()))")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: checksForAppUpdates) { _, isChecking in
            guard isChecking else { return }
            Task { await library.checkForUpdates(library.apps) }
        }
        .task { readStandings() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // The user may have changed the login item in System Settings, so read it again.
            readStandings()
        }
        .confirmationDialog("Remove Peel from this Mac?", isPresented: $isConfirmingSelfRemoval) {
            Button("Remove Peel", role: .destructive) {
                Task {
                    await selfUninstall.run(installedApps: library.apps, helper: helper, pausing: background) { result in
                        await history.record(result, tool: .applications, source: "Peel", sizes: [:])
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Peel, the files that are certainly its own, and its folder in Application Support go to the Trash, and its settings are cleared. That folder holds History, your exclusions, and Saved Settings. The space is freed when you empty the Trash.")
        }
        .alert("Peel couldn’t remove itself.", isPresented: isShowingSelfRemovalFailure) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(verbatim: selfUninstall.failure ?? "")
        }
        .alert("Peel is in the Trash, but a few things stayed behind.", isPresented: .constant(selfUninstall.leftBehind != nil)) {
            Button("Quit Peel") { selfUninstall.quit() }
        } message: {
            Text(verbatim: selfUninstall.leftBehind ?? "")
        }
    }
}

extension GeneralSettingsView {
    fileprivate struct Muted: Identifiable {
        let identifier: String
        let app: InstalledApp?
        let isIgnored: Bool
        let skippedVersion: String?

        var id: String { identifier }
        var name: String { app?.name ?? identifier }
    }

    fileprivate var muted: [Muted] {
        let identifiers = library.ignoredIdentifiers.union(library.skippedVersions.keys)
        return identifiers.map { identifier in
            Muted(
                identifier: identifier,
                app: library.apps.first { $0.bundleIdentifier == identifier },
                isIgnored: library.ignoredIdentifiers.contains(identifier),
                skippedVersion: library.skippedVersions[identifier]
            )
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    @ViewBuilder
    fileprivate func mutedRow(_ item: Muted) -> some View {
        HStack(spacing: 8) {
            if let app = item.app {
                AppIcon(url: app.url)
                    .frame(width: 16, height: 16)
            } else {
                Image(systemName: "questionmark.app")
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: item.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if item.isIgnored {
                    Text("Never checked")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let version = item.skippedVersion {
                    Text("Version \(version) skipped")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            // Checks right away, as the button's title says, rather than at the next scheduled check.
            Button {
                library.unmute(item.identifier)
                if let app = item.app {
                    Task { await library.checkForUpdates([app], force: true) }
                }
            } label: {
                Text("Check Again")
                    .minimumTarget()
            }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("Check \(item.name) for updates again"))
        }
    }
}

extension GeneralSettingsView {
    fileprivate func toggle(_ title: LocalizedStringResource, isOn: Binding<Bool>, _ detail: LocalizedStringResource) -> some View {
        LabeledContent {
            Toggle(isOn: isOn) { EmptyView() }
                .labelsHidden()
                .accessibilityLabel(Text(title))
        } label: {
            titled(title, detail)
        }
    }
}

extension GeneralSettingsView {
    fileprivate func showsInSidebar(_ tool: Tool) -> Binding<Bool> {
        Binding(
            get: { !Tool.hidden(in: hiddenTools).contains(tool) },
            set: { shows in
                var hidden = Tool.hidden(in: hiddenTools)
                if shows { hidden.remove(tool) } else { hidden.insert(tool) }
                hiddenTools = Tool.storing(hidden: hidden)
            }
        )
    }

    fileprivate var isShowingSelfRemovalFailure: Binding<Bool> {
        Binding(
            get: { selfUninstall.failure != nil },
            set: { if !$0 { selfUninstall.failure = nil } }
        )
    }

    /// The cask Homebrew installed this copy of Peel from, found by the rule the Applications list follows.
    fileprivate var ownCask: HomebrewPackage? {
        guard let app = library.apps.first(where: \.isTheRunningCopy) else { return nil }
        return CaskEvidence.installedCask(for: app, in: (homebrew.packages ?? []).filter { $0.kind == .cask })
    }
}

private struct HelperSettingsView: View {
    @Environment(HelperModel.self) private var helper

    /// The helper's buttons have no label beside them, so each is centered in its row.
    var body: some View {
        Form {
            Section {
                LabeledContent {
                    statusBadge
                } label: {
                    HStack(spacing: 5) {
                        Text("Status")
                        InfoNote(
                            name: String(localized: "Helper"),
                            detail: Text("A small tool with administrator rights. It moves items to the Trash, puts them back, starts or stops background items, and forgets installer receipts. It takes no other orders."),
                            symbol: "lock.shield"
                        )
                    }
                }
            }

            Section {
                switch helper.standing {
                case .notInstalled:
                    Button("Install Helper", systemImage: "lock.shield") {
                        helper.install()
                    }
                    .centeredInRow()
                case .waitingForApproval:
                    Text("Allow Peel in System Settings under Login Items & Extensions.")
                        .font(.callout)
                    // Opens System Settings instead of registering again, which returns an error in this state
                    // (`SMAppService.h`).
                    Button("Open System Settings", systemImage: "gearshape") {
                        PrivilegedHelper.openLoginItemsSettings()
                    }
                    .centeredInRow()
                case .notThisAccount:
                    Text("Only an administrator can use the helper. Log in as an administrator to remove items that need one.")
                        .font(.callout)
                    if helper.isEnabled {
                        uninstallButton
                    }
                case .notAnswering:
                    // Several causes share this message: an older or newer helper, a signature that doesn't
                    // match, or a helper that didn't start.
                    Text("Peel’s helper isn’t answering. Repairing it installs the one this version of Peel works with.")
                        .font(.callout)
                    Button("Repair Helper", systemImage: "arrow.clockwise") {
                        Task { await helper.repair() }
                    }
                    .disabled(helper.isChanging)
                    .centeredInRow()
                    uninstallButton
                case .ready:
                    uninstallButton
                }
            }
            .listRowBackground(Color.clear)
        }
        .formStyle(.grouped)
        .task(id: helper.status) {
            await helper.checkConnection()
        }
        .alert(helperFailureTitle, isPresented: isShowingFailure) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(verbatim: helper.failure?.reason ?? "")
        }
    }

    private var uninstallButton: some View {
        Button("Uninstall Helper", systemImage: "trash", role: .destructive) {
            Task { await helper.uninstall() }
        }
        .disabled(helper.isChanging)
        .centeredInRow()
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch helper.standing {
        case .notThisAccount:
            state("Needs an administrator", "person.crop.circle.badge.exclamationmark", .orange)
        case .notAnswering:
            state("Not answering", "exclamationmark.triangle", .orange)
        case .ready:
            state("Installed", "checkmark.circle", .green)
        case .waitingForApproval:
            state("Needs approval, or was turned off", "clock", .orange)
        case .notInstalled:
            state("Not installed", "minus.circle", .secondary)
        }
    }

    private var helperFailureTitle: Text {
        switch helper.failure?.action {
        case .install: Text("The helper couldn’t be installed.")
        case .repair: Text("The helper couldn’t be repaired.")
        case .uninstall: Text("The helper couldn’t be uninstalled.")
        case nil: Text(verbatim: "")
        }
    }

    private var isShowingFailure: Binding<Bool> {
        Binding(
            get: { helper.failure != nil },
            set: { if !$0 { helper.failure = nil } }
        )
    }
}
