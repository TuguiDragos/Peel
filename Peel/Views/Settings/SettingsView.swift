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
    /// Whether the tabs have the Settings window's size, the same for every tab, so the window holds still as they
    /// change. On the Settings page the tabs fill the column.
    var isInTheWindow = false

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

    @ViewBuilder
    private func fitted(_ tab: some View) -> some View {
        if isInTheWindow {
            tab.frame(width: 680, height: SettingsView.height)
        } else {
            tab
        }
    }
}

/// The Settings window's content. The `Settings` scene sizes the window to fit it, so it keeps one size whichever tab
/// is open, and a tab with more to show scrolls.
struct SettingsView: View {
    static let height: CGFloat = 520

    var body: some View {
        if #available(macOS 27, *) {
            SettingsWindowTabs()
        } else {
            SettingsTabs(isInTheWindow: true)
        }
    }
}

/// The Settings window on macOS 27: its tabs as one capsule in the toolbar, as on the Settings page of the main
/// window, since a tab view in a settings window shows them as separate toolbar buttons whatever its style.
@available(macOS 27, *)
private struct SettingsWindowTabs: View {
    @AppStorage(SettingsKey.pane) private var pane = SettingsPane.general.rawValue

    var body: some View {
        page
            .frame(width: 760, height: SettingsView.height)
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Settings", selection: $pane) {
                        Text("General").tag(SettingsPane.general.rawValue)
                        Text("Exclusions").tag(SettingsPane.exclusions.rawValue)
                        Text("Privacy").tag(SettingsPane.privacy.rawValue)
                        Text("Helper").tag(SettingsPane.helper.rawValue)
                    }
                    .pickerStyle(.tabs)
                }
            }
    }

    @ViewBuilder
    private var page: some View {
        switch SettingsPane(rawValue: pane) ?? .general {
        case .general: GeneralSettingsView()
        case .exclusions: ExclusionsSettingsView()
        case .privacy: PrivacySettingsView()
        case .helper: HelperSettingsView()
        }
    }

    private var title: Text {
        switch SettingsPane(rawValue: pane) ?? .general {
        case .general: Text("General")
        case .exclusions: Text("Exclusions")
        case .privacy: Text("Privacy")
        case .helper: Text("Helper")
        }
    }
}

enum SettingsKey {
    static let pane = "settingsPane"
    static let checksForAppUpdates = "checksForAppUpdates"
    static let watchesTrash = "watchesTrash"
    static let showsInMenuBar = "showsInMenuBar"
    static let hidesFromDock = "hidesFromDock"
    static let warnsWhenDiskIsNearlyFull = "lowDiskSpace.warns"
    static let toldDiskIsNearlyFull = "lowDiskSpace.told"
    /// How many older removals History's page last said it no longer lists.
    static let toldNoLongerListed = "history.toldNoLongerListed"
    static let toldRefusalsNoLongerListed = "history.toldRefusalsNoLongerListed"
    /// The tools the person chose to show or leave out of the sidebar (`SidebarChoices`).
    static let sidebarTools = "sidebar.tools"
    /// The tools left out before each tool had a default, carried into `sidebarTools` once.
    private static let hiddenToolsBefore = "sidebar.hiddenTools"
    /// The `peel` tool reads these four keys too, so they are defined once, in PeelCore.
    static let updateSource = UpdatePreferences.Key.source
    static let ignoredUpdateApps = UpdatePreferences.Key.ignoredApps
    static let skippedUpdateVersions = UpdatePreferences.Key.skippedVersions
    static let updateMemory = UpdateMemories.key
    static let updatesBeingChecked = "updates.beingChecked"
    static let announcedUpdates = "updates.announced"

    /// Nil once the link leads to this copy's tool, and while something that may not be Peel's is where it goes.
    static func commandLineInstallCommand(
        for standing: CommandLineTool.Standing = HomeModel.commandLineStanding
    ) -> String? {
        CommandLineTool.installCommand(
            embedded: Bundle.main.bundleURL.appending(path: "Contents/Helpers/peel"),
            standing: standing
        )
    }
}

extension SettingsKey {
    /// Carries the tools a person left out before each tool had a default into their choices, once. An empty list
    /// carries no choice, so every tool starts at its default.
    static func keepSidebarChoicesAsBefore() {
        let defaults = UserDefaults.standard
        guard let hidden = defaults.string(forKey: hiddenToolsBefore) else { return }
        if defaults.string(forKey: sidebarTools) == nil {
            defaults.set(SidebarChoices(hiddenBefore: hidden).stored, forKey: sidebarTools)
        }
        defaults.removeObject(forKey: hiddenToolsBefore)
    }

    /// With no value yet, Peel shows in the menu bar exactly when it watches the Trash.
    static func showInMenuBarAsBefore() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: showsInMenuBar) == nil else { return }
        defaults.set(defaults.bool(forKey: watchesTrash), forKey: showsInMenuBar)
    }
}

/// A small capsule that shows a state, such as On or Not installed, with a tinted symbol. Settings keeps the
/// system's plain look here rather than Peel's sticker badges.
private func state(_ title: LocalizedStringResource, _ symbol: String, _ tint: Color) -> some View {
    HStack(spacing: 4) {
        Text(title)
        Image(systemName: symbol)
            .foregroundStyle(tint)
            // The words are the whole state.
            .accessibilityHidden(true)
    }
    .font(.caption)
    .foregroundStyle(.secondary)
    .padding(.horizontal, 8)
    .padding(.vertical, 3)
    .background(.quaternary, in: .capsule)
}

struct GeneralSettingsView: View {
    static let hidesFromDockNote: LocalizedStringResource = "While Peel shows in the menu bar, its icon leaves the Dock when you close its last window, and comes back when you open Peel again from the menu bar, Finder, or Spotlight. If the menu bar is full, macOS may hide Peel there, so open it from Finder or Spotlight."
    static let checkForUpdatesNote: LocalizedStringResource = "Peel asks the feed of each app, the App Store, or Homebrew for the latest version, and never installs anything on its own. With this off, Peel looks for its own updates only when you choose Check for Updates."
    static let preferUpdatesNote: LocalizedStringResource = "Automatic asks Homebrew first about an app it installed, then the feed of the app or the App Store. Any other choice asks the source you prefer first. The catalog of Homebrew answers last, for an app Homebrew did not install."
    static let diskAlmostFullNote: LocalizedStringResource = "While Peel runs, it sends a notification when less than a tenth of the disk with your home folder is free. Clicking it opens Space."
    static let trashClosed: LocalizedStringResource = "Peel cannot read your Trash"
    static let trashClosedNote: LocalizedStringResource = "The permissions of the folder keep this account out, so Peel is not watching it."
    static let trashNotWatched: LocalizedStringResource = "Not watching the Trash right now"
    static let trashNotWatchedNote: LocalizedStringResource = "Peel tries again each time you come back to it."
    static let notificationsAreOff: LocalizedStringResource = "Notifications are off for Peel"
    static let cannotOfferLeftovers: LocalizedStringResource = "So Peel cannot offer to remove what an app left behind."
    static let cannotWarnDiskFull: LocalizedStringResource = "So Peel cannot warn you when the disk is almost full."
    static let moveToApplicationsFirst: LocalizedStringResource = "Move Peel to the Applications folder first"
    static let removedWithHomebrew: LocalizedStringResource = "Homebrew installed this copy of Peel, so remove it with Homebrew."
    static let removedWithHomebrewNote: LocalizedStringResource = "Homebrew deletes the app instead of moving it to the Trash, and moves the Peel folder in Application Support to the Trash, with History, your exclusions, and the Terminal page settings. It also stops the Peel helper, asking for an administrator password, and deletes its record of what it moved, so History can no longer put those items back."
    static let removePeelNote: LocalizedStringResource = "Peel removes its helper and login item, moves itself, its own files, and its folder in Application Support to the Trash, clears its settings, and quits. That folder holds History and your exclusions. What you set in Tweaks and on the Terminal page stays."
    static let removePeelQuestion: LocalizedStringResource = "Peel, its own files, and its folder in Application Support go to the Trash, and its settings are cleared. That folder holds History, your exclusions, and your saved settings. What you set in Tweaks and on the Terminal page stays as it is."
    static let waitingForHomebrew: LocalizedStringResource = "Waiting for Homebrew…"
    static let homebrewSaidNothing: LocalizedStringResource = "Homebrew did not say what is installed"
    static let homebrewMustUpdate: LocalizedStringResource = "Homebrew needs to update first"
    static let homebrewNotRun: LocalizedStringResource = "Peel does not run this Homebrew"
    static let removedWithHomebrewToo: LocalizedStringResource = "A copy Homebrew installed is removed with Homebrew."

    static func linkBreaksIfPeelMoves(_ path: String) -> LocalizedStringResource {
        "The link points at Peel where it is now, \(path), so it breaks if Peel moves."
    }

    /// What the command-line tool's note says to do, as the row stands: nothing to run once `peel` is on the path,
    /// a line for the shell on an account that isn't an administrator's, and no command while none is offered.
    static func commandLineNote(
        installed: Bool, standardAccount: Bool, offersACommand: Bool
    ) -> LocalizedStringResource {
        if installed {
            return "`peel` is on your path. Type `peel --help` in Terminal to see what it can do."
        }
        if standardAccount {
            return "Add the line below to the startup file of your shell to use `peel` from this account, then type `peel --help` in Terminal to see what it can do."
        }
        guard offersACommand else {
            return "`peel` does from Terminal what Peel does in its window. The line below says why there is no command to run yet."
        }
        return "Run the command in Terminal to use `peel` from anywhere, then type `peel --help` to see what it can do."
    }

    @State private var commandLine = HomeModel.commandLineStanding
    private var installCommand: String? { SettingsKey.commandLineInstallCommand(for: commandLine) }
    private static let place = CommandLineTool.place()
    private static let embeddedTool = Bundle.main.bundleURL.appending(path: "Contents/Helpers/peel")
    private var isStandardAccount: Bool { !helper.isAdministrator }
    private static let blockAhead = SelfRemoval.blockAhead(of: Bundle.main.bundleURL)

    @AppStorage(SettingsKey.checksForAppUpdates) private var checksForAppUpdates = true
    @AppStorage(SettingsKey.updateSource) private var updateSource = UpdateSource.automatic.rawValue
    @AppStorage(SettingsKey.watchesTrash) private var watchesTrash = false
    @AppStorage(SettingsKey.showsInMenuBar) private var showsInMenuBar = false
    @AppStorage(SettingsKey.hidesFromDock) private var hidesFromDock = false
    @AppStorage(SettingsKey.warnsWhenDiskIsNearlyFull) private var warnsWhenDiskIsNearlyFull = false
    @AppStorage(SettingsKey.sidebarTools) private var sidebarTools = ""
    @Environment(TrashMonitor.self) private var trashMonitor
    @Environment(AppLibrary.self) private var library
    @Environment(HomebrewLibrary.self) private var homebrew
    @Environment(HelperModel.self) private var helper
    @Environment(RemovalHistoryStore.self) private var history
    @Environment(ExclusionsStore.self) private var exclusions
    @Environment(StandingWork.self) private var background
    @Environment(HomeModel.self) private var home
    @Environment(SelfUninstall.self) private var selfUninstall
    @State private var isChoosingSidebarTools = false
    // The widest tool symbol at the body size, so the titles of the tools line up.
    @ScaledMetric(relativeTo: .body) private var toolSymbolWidth = 20.0
    @State private var isConfirmingSelfRemoval = false

    private func readStandings() {
        commandLine = HomeModel.commandLineStanding
        SavedSettings.shared.reload()
    }

    var body: some View {
        Form {
            Section {
                // An `HStack` centers the button on a summary that takes two lines, as Saved Settings' rows do.
                HStack(spacing: 8) {
                    Text(sidebarToolsSummary)
                    Spacer(minLength: 8)
                    Button("Choose Tools…") {
                        isChoosingSidebarTools = true
                    }
                    .popover(isPresented: $isChoosingSidebarTools, arrowEdge: .bottom) {
                        sidebarToolsChoice
                    }
                }
            } header: {
                titled("Sidebar", "Turn a tool off to leave it out of the sidebar. The View menu and Shortcuts still open it.")
            }

            Section("Updates") {
                toggle("Check for app updates", isOn: $checksForAppUpdates, Self.checkForUpdatesNote)
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
                    .disabled(!checksForAppUpdates)
                } label: {
                    titled("Prefer updates from", Self.preferUpdatesNote)
                }
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
                toggle("Show in Menu Bar", isOn: $showsInMenuBar,
                       "Peel stays in the menu bar after you close its window, with what each tool found and the updates waiting. Without it, Peel quits when you close its window.")
                toggle("Hide from the Dock while no window is open", isOn: $hidesFromDock, Self.hidesFromDockNote,
                       isDisabled: !showsInMenuBar)
                toggle("Watch the Trash", isOn: $watchesTrash,
                       "When you move an app to the Trash yourself, Peel offers to remove the files it left behind. Peel watches the Trash while it is open, or while it is in the menu bar.")
                if watchesTrash, trashMonitor.status == .needsFullDiskAccess {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            StatusLabel(title: Text("Peel needs Full Disk Access to watch the Trash."), systemImage: "lock.trianglebadge.exclamationmark")
                            if home.needsRelaunchForFullDiskAccess {
                                Text(verbatim: HomeModel.reopenForFullDiskAccess)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        // Full Disk Access applies only to a new process, so once it may have been given, Peel offers
                        // to reopen.
                        if home.needsRelaunchForFullDiskAccess {
                            Button("Reopen Peel") { home.relaunch() }
                        }
                        Button("Open System Settings") {
                            home.openFullDiskAccessSettings()
                        }
                    }
                } else if watchesTrash, trashMonitor.status == .closedByPermissions {
                    NotedStatus(title: Text(Self.trashClosed), note: Text(Self.trashClosedNote))
                } else if watchesTrash, trashMonitor.status == .unavailable {
                    NotedStatus(title: Text(Self.trashNotWatched), note: Text(Self.trashNotWatchedNote))
                }
                if watchesTrash, PeelNotifications.areTurnedOff(home.notificationStatus) {
                    notificationsOff(Text(Self.cannotOfferLeftovers))
                }
                toggle("Warn when the disk is almost full", isOn: $warnsWhenDiskIsNearlyFull, Self.diskAlmostFullNote)
                if warnsWhenDiskIsNearlyFull, PeelNotifications.areTurnedOff(home.notificationStatus) {
                    notificationsOff(Text(Self.cannotWarnDiskFull))
                }
                // A binding, not `onChange`: macOS's own answer landing in the model must not register again.
                toggle("Open Peel at login", isOn: Binding(get: { home.loginItem.isOn }, set: { home.loginItem.set(on: $0) }),
                       "Starts Peel when you log in. “Watch the Trash” works only while Peel is running.",
                       isDisabled: !home.loginItem.isKnown)
                if home.loginItem.needsApproval {
                    HStack {
                        StatusLabel(title: Text("Peel is turned off in Login Items & Extensions, so macOS won’t start it."))
                        Spacer()
                        Button("Open System Settings") {
                            SMAppService.openSystemSettingsLoginItems()
                        }
                    }
                }
                if let failure = home.loginItem.failure {
                    StatusLabel(title: Text(failure))
                        .textSelection(.enabled)
                }
            }

            Section("Elsewhere on This Mac") {
                LabeledContent {
                    Button("Open System Settings") {
                        FIFinderSyncController.showExtensionManagementInterface()
                    }
                } label: {
                    // Uses `HomeModel`'s state, so Home and Settings can't show different answers.
                    let isOn = home.state(of: .finderExtension) == .on
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text("Finder extension")
                        if home.hasChecked {
                            state(isOn ? "On" : home.isFinderExtensionFromAnotherCopy ? "On in another copy of Peel" : "Off",
                                  isOn ? "checkmark.circle" : "minus.circle",
                                  isOn ? .green : .secondary)
                        } else {
                            state("Checking…", "hourglass", .secondary)
                        }
                        InfoNote(
                            name: String(localized: "Finder extension"),
                            detail: Text("Control-click an app in Finder and choose Uninstall with Peel to see what it leaves behind.")
                        )
                    }
                }
                LabeledContent {
                    if commandLine == .installed {
                        state("Installed", "checkmark.circle", .green)
                    } else if isStandardAccount {
                        state("Needs an administrator", "person.crop.circle.badge.exclamationmark", .orange)
                    } else if let installCommand {
                        CopyButton(text: installCommand)
                    }
                } label: {
                    titled(
                        "Command-line tool",
                        Self.commandLineNote(
                            installed: commandLine == .installed, standardAccount: isStandardAccount,
                            offersACommand: installCommand != nil
                        )
                    )
                }
                switch Self.place {
                case .applications:
                    EmptyView()
                case .temporaryCopy:
                    Text("Peel is running from a copy macOS made because it is still marked as downloaded. Move Peel to the Applications folder and open it from there.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .readOnlyVolume:
                    Text("Peel is running from a read-only disk, such as the disk image it came on. Move Peel to the Applications folder and open it from there.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .elsewhere:
                    if commandLine == .installed || installCommand != nil, !isStandardAccount {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(Self.moveToApplicationsFirst)
                            InfoNote(
                                about: Text(Self.moveToApplicationsFirst),
                                detail: Text(Self.linkBreaksIfPeelMoves(Bundle.main.bundleURL.abbreviatedPath)),
                                isAlbum: false
                            )
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                if [.applications, .elsewhere].contains(Self.place), commandLine != .installed {
                    if isStandardAccount {
                        if let shell = CommandLineTool.shellLine(embedded: Self.embeddedTool) {
                            CopyableLines(
                                caption: Text("Putting `peel` on the path takes an administrator. To use it from this account, add this line to \(shell.file), then open a new Terminal window."),
                                lines: [shell.line]
                            )
                        }
                    } else if let installCommand {
                        Text(verbatim: installCommand)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    } else if case .somethingElse(let other) = commandLine {
                        Text(HomeModel.inTheToolsPlace(other))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            SavedSettingsSection()

            Section {
                let way = SelfUninstall.way(
                    cask: ownCask,
                    brew: homebrew.wordForTerminal,
                    homebrewKnowsItsApps: homebrew.knowsWhetherItInstalledPeel,
                    unanswered: homebrew.unanswered
                )
                if case .homebrew(let command) = way {
                    LabeledContent {
                        CopyButton(text: command)
                    } label: {
                        titled("Remove Peel", Self.removedWithHomebrewNote)
                    }
                    Text(Self.removedWithHomebrew)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(verbatim: command)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                } else {
                    // The button is taller than a row, and `LabeledContent` would align the title with its top
                    // edge. An `HStack` centers the title and the button vertically.
                    HStack {
                        titled("Remove Peel", Self.removePeelNote)
                        Spacer(minLength: 8)
                        Button("Remove Peel") {
                            isConfirmingSelfRemoval = true
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        // Disabled until the app list has loaded: a file Peel shares with another app would look like
                        // Peel's alone.
                        .disabled(
                            selfUninstall.isRunning || !library.hasLoaded || way.waitsForHomebrew
                                || !history.mayMove || Self.blockAhead != nil || waitsForAnAdministrator
                                || helper.isChanging
                        )
                    }
                    if selfUninstall.isRunning {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Removing Peel…")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    } else if exclusions.exclusions.isUnreadable {
                        Text(verbatim: exclusions.nothingMovesUntilStartedOver)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else if let why = history.readProblem {
                        Text(verbatim: why.said(after: String(localized: "Peel removes nothing until you start History over, so that everything it moves can be put back."), about: history.historyFile))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else if let problem = history.writeProblem {
                        Text(problem.explanation())
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else if let block = Self.blockAhead {
                        Text(SelfUninstall.explanation(
                            of: block, isAdministrator: helper.isAdministrator,
                            helperIsRegistered: helper.isRegistered
                        ))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else if waitsForAnAdministrator {
                        Text(verbatim: SelfUninstall.helperGoesFirst)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else if way == .waitingForHomebrew {
                        homebrewState(Self.waitingForHomebrew)
                    } else if case .homebrewDidNotAnswer(let why) = way {
                        HStack {
                            switch why {
                            case .readingFailed: homebrewState(Self.homebrewSaidNothing)
                            case .hasToUpdate: homebrewState(Self.homebrewMustUpdate)
                            case .notRun: homebrewState(Self.homebrewNotRun)
                            }
                            Spacer()
                            Button("Open \(String(localized: Tool.homebrew.title))") { Navigator.shared.show(.homebrew) }
                        }
                    }
                }
                // Homebrew removes the links its cask made, and no other.
                if selfUninstall.leavesCommandLineTool(way: way, helper: helper.status),
                   ownCask?.commandLinks.contains(CommandLineTool.path) != true {
                    VStack(alignment: .leading, spacing: 4) {
                        Group {
                            if isStandardAccount {
                                Text("Removing Peel leaves the peel command in place. To remove it too, an administrator runs this command in Terminal:")
                            } else {
                                Text("Removing Peel leaves the peel command in place. To remove it too, run this command in Terminal:")
                            }
                        }
                        .font(.callout)
                        Text(verbatim: SelfUninstall.removeCommand)
                            .font(.caption.monospaced())
                    }
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
        .task {
            readStandings()
            await home.loginItem.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // The user may have changed the login item in System Settings, or a saved copy in Finder.
            readStandings()
            Task { await home.loginItem.refresh() }
        }
        .confirmationDialog("Remove Peel from this Mac?", isPresented: $isConfirmingSelfRemoval) {
            Button("Remove Peel", role: .destructive) {
                Task {
                    await history.moving(tool: .applications, source: "Peel") {
                        await selfUninstall.run(
                            installedApps: library.apps,
                            helper: helper,
                            pausing: background
                        ) { result in
                            await history.record(result, tool: .applications, source: "Peel", sizes: [:])
                        }
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            let files = Text(Self.removePeelQuestion)
            if let first = SelfUninstall.whatGoesFirst(
                helperIsRegistered: helper.isRegistered, opensAtLogin: home.loginItem.isOn
            ) {
                Text("\(first)\n\n\(files)")
            } else {
                files
            }
        }
    }
}

extension GeneralSettingsView {
    fileprivate struct Muted: Identifiable {
        let reference: String
        let app: InstalledApp?
        /// The listed app's name, or the Finder name of a copy macOS knows elsewhere.
        let name: String
        let isIgnored: Bool
        let skippedVersion: String?

        var id: String { reference }
    }

    fileprivate var muted: [Muted] {
        let references = library.ignoredApps.union(library.skippedVersions.keys)
        return references.map { reference in
            Muted(
                reference: reference,
                app: library.apps.first { $0.reference == reference },
                name: library.name(forReference: reference),
                isIgnored: library.ignoredApps.contains(reference),
                skippedVersion: library.skippedVersions[reference]
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
                    .accessibilityRepresentation { Text("Not installed") }
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: item.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if item.isIgnored {
                    Text("Not checked")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let version = item.skippedVersion {
                    Text("Version \(UpdateStatus.shownVersion(of: version)) skipped")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            // Checks right away, as the button's title says, rather than at the next scheduled check.
            Button {
                library.unmute(item.reference)
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
    /// A switch row. `isDisabled` disables the switch alone: disabling the whole row would disable the circled i beside
    /// the title too, so its note couldn't be read while it explains why the switch is off.
    fileprivate func toggle(
        _ title: LocalizedStringResource,
        isOn: Binding<Bool>,
        _ detail: LocalizedStringResource,
        isDisabled: Bool = false
    ) -> some View {
        LabeledContent {
            Toggle(isOn: isOn) { EmptyView() }
                .labelsHidden()
                .accessibilityLabel(Text(title))
                .disabled(isDisabled)
        } label: {
            titled(title, detail)
        }
    }

    /// Why Remove Peel waits for Homebrew, in a few words, with why that matters in a circled i.
    fileprivate func homebrewState(_ state: LocalizedStringResource) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(state)
            InfoNote(about: Text(state), detail: Text(Self.removedWithHomebrewToo), isAlbum: false)
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }

    fileprivate func notificationsOff(_ note: Text) -> some View {
        HStack {
            NotedStatus(title: Text(Self.notificationsAreOff), note: note, systemImage: "bell.slash")
            Spacer()
            Button("Open System Settings") {
                home.openNotificationSettings()
            }
        }
    }
}

extension GeneralSettingsView {
    private var sidebarToolsSummary: LocalizedStringResource {
        let hidden = Tool.hidden(by: SidebarChoices(stored: sidebarTools), homebrew: homebrew)
        return Self.sidebarSummary(hidden: Tool.Group.allCases.flatMap(\.tools).count(where: hidden.contains))
    }

    /// How many tools are off. Choose Tools… names them, and English agrees its verb through the catalog's variations.
    static func sidebarSummary(hidden: Int) -> LocalizedStringResource {
        hidden == 0 ? "Every tool is in the sidebar." : "\(hidden) more tools are available."
    }

    private var sidebarToolsChoice: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Tool.Group.allCases.flatMap(\.tools).filter(\.canBeHidden)) { tool in
                Toggle(isOn: showsInSidebar(tool)) {
                    Label { Text(tool.title) } icon: { Image(systemName: tool.systemImage) }
                }
                .toggleStyle(.checkbox)
            }
        }
        .labelReservedIconWidth(toolSymbolWidth)
        .padding(16)
    }

    fileprivate func showsInSidebar(_ tool: Tool) -> Binding<Bool> {
        Binding(
            get: {
                !Tool.hidden(by: SidebarChoices(stored: sidebarTools), homebrew: homebrew).contains(tool)
            },
            set: { shows in
                var choices = SidebarChoices(stored: sidebarTools)
                choices.choose(tool.rawValue, shows: shows)
                sidebarTools = choices.stored
            }
        )
    }

    private var waitsForAnAdministrator: Bool {
        SelfUninstall.waitsForAnAdministrator(isAdministrator: helper.isAdministrator, status: helper.status)
    }

    /// The cask Homebrew installed this copy of Peel from, found by the rule the Applications list follows.
    fileprivate var ownCask: HomebrewPackage? {
        guard let app = library.apps.first(where: \.isTheRunningCopy) else { return nil }
        return CaskEvidence.installedCask(for: app, in: (homebrew.packages ?? []).filter { $0.kind == .cask })
    }
}

struct HelperSettingsView: View {
    static let about: LocalizedStringResource = "A small tool with administrator rights that moves items to the Trash and back, controls background items, and forgets installer receipts. It takes no other orders."
    static let notAnswering: LocalizedStringResource = "The Peel helper is not answering"
    static let notAnsweringNote: LocalizedStringResource = "Repair installs the Peel helper that matches this version of Peel."

    @Environment(HelperModel.self) private var helper
    @State private var failure: HelperModel.Failure?
    @State private var isConfirmingUninstall = false

    var body: some View {
        Form {
            Section {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        status
                        Spacer(minLength: 8)
                        actions
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        status
                        ActionRow { actions }
                    }
                }
                // Several causes share this state: an older or newer helper, a signature that doesn't match, or a
                // helper that didn't start.
                if helper.standing == .notAnswering {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(Self.notAnswering)
                        InfoNote(about: Text(Self.notAnswering), detail: Text(Self.notAnsweringNote), isAlbum: false)
                    }
                    .font(.callout)
                } else if let explanation {
                    explanation
                        .font(.callout)
                }
            }
        }
        .formStyle(.grouped)
        .task {
            await helper.checkConnection()
        }
        .helperFailureAlert($failure)
        .confirmationDialog("Uninstall Peel’s helper?", isPresented: $isConfirmingUninstall) {
            Button("Uninstall Helper", role: .destructive) {
                Task { failure = await helper.uninstall() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The helper serves every account on this Mac, so this removes it for all of them. Until it is installed again, Peel can’t move what only an administrator can change.")
        }
    }

    /// The state with its word and its note, which stay together wherever the buttons go.
    @ViewBuilder
    private var status: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            InfoNote(
                name: String(localized: "Helper"),
                detail: Text(Self.about),
                symbol: "lock.shield"
            )
            Text("Status")
            statusBadge
        }
    }

    /// What can be done about the state, the step it asks for last.
    @ViewBuilder
    private var actions: some View {
        if helper.isRegistered {
            uninstallButton
        }
        switch helper.standing {
        case .notInstalled:
            if helper.standing.offersInstall(registeredByAnotherCopy: helper.isRegisteredByAnotherCopy) {
                Button("Install Helper") {
                    Task { failure = await helper.install() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(helper.isChanging)
            }
        case .waitingForApproval:
            // Opens System Settings instead of registering again, which returns an error in this state
            // (`SMAppService.h`).
            Button("Open System Settings") {
                PrivilegedHelper.openLoginItemsSettings()
            }
            .buttonStyle(.borderedProminent)
        case .ready:
            EmptyView()
        case .notAnswering:
            Button("Repair Helper") {
                Task { failure = await helper.repair() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(helper.isChanging)
        }
    }

    /// What the helper's state asks of the person, said under its row.
    private var explanation: Text? {
        switch helper.standing {
        case .notInstalled where helper.isRegisteredByAnotherCopy:
            Text(helper.standing.whyItCannotAct(registeredByAnotherCopy: true))
        case .notInstalled:
            helper.isAdministrator
                ? nil
                : Text("On this account, Peel asks for an administrator name and password before it installs, repairs, or removes the helper.")
        case .waitingForApproval:
            Text("Allow Peel in System Settings > General > Login Items & Extensions.")
        case .notAnswering:
            nil
        case .ready:
            helper.isAdministrator
                ? nil : Text("Peel asks for an administrator’s name and password each time this account needs the helper.")
        }
    }

    private var uninstallButton: some View {
        Button("Uninstall Helper", role: .destructive) {
            isConfirmingUninstall = true
        }
        .disabled(helper.isChanging)
    }

    private var statusBadge: some View {
        let (symbol, tint): (String, Color) = if helper.changing != nil || !helper.hasChecked {
            ("hourglass", .secondary)
        } else {
            switch helper.standing {
            case .notAnswering: ("exclamationmark.triangle", .orange)
            case .ready: ("checkmark.circle", .green)
            case .waitingForApproval: ("clock", .orange)
            case .notInstalled where helper.isRegisteredByAnotherCopy: ("exclamationmark.triangle", .orange)
            case .notInstalled: ("minus.circle", .secondary)
            }
        }
        return state(helper.stateWords, symbol, tint)
    }
}
