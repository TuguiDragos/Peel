import PeelCore
import SwiftUI

/// Decides whether Peel quits when its window closes, and when a quit goes ahead (`QuitGuard`). SwiftUI's
/// documentation for `Window` says an app whose primary scene is a single window quits when that window closes.
/// Peel keeps running without a window only while it shows in the menu bar, so it is never running unseen.
@MainActor
final class PeelAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ application: NSApplication) -> Bool {
        !UserDefaults.standard.bool(forKey: SettingsKey.showsInMenuBar)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        QuitGuard.shared.replyToQuit()
    }
}

@main
struct PeelApp: App {
    @NSApplicationDelegateAdaptor(PeelAppDelegate.self) private var delegate
    static let mainWindowID = "main"
    /// How often the update round runs. The shortest wait an app can have is six hours, after a failed check
    /// (`UpdateSchedule.afterFailure`), so an hourly round checks each app soon after it is due.
    private static let updateCheckInterval: TimeInterval = 60 * 60
    private static let freeSpaceCheckInterval: TimeInterval = 5 * 60

    @Environment(\.openWindow) private var openWindow
    @AppStorage(SettingsKey.checksForAppUpdates) private var checksForAppUpdates = true
    @AppStorage(SettingsKey.watchesTrash) private var watchesTrash = false
    @AppStorage(SettingsKey.showsInMenuBar) private var showsInMenuBar = false
    @AppStorage(SettingsKey.warnsWhenDiskIsNearlyFull) private var warnsWhenDiskIsNearlyFull = false
    @State private var trashMonitor = TrashMonitor()
    @State private var notifications: PeelNotifications
    @State private var stats = LifetimeStats()
    @State private var found = FoundLastTimeStore()
    @State private var library: AppLibrary
    @State private var orphans: OrphanLibrary
    @State private var projects: ProjectLibrary
    @State private var installers: InstallerLibrary
    @State private var tweaks = TweakLibrary()
    @State private var terminal = TerminalLibrary()
    @State private var shell = ShellLibrary()
    @State private var git = GitLibrary()
    @State private var ssh = SSHLibrary()
    @State private var terminalTools = TerminalToolLibrary()
    @State private var extensions = ExtensionLibrary()
    @State private var cloud = CloudLibrary()
    @State private var backgroundItems = BackgroundItemLibrary()
    @State private var packages = PackageLibrary()
    @State private var developer: DeveloperLibrary
    @State private var duplicates: DuplicateLibrary
    @State private var fileSearch: FileSearchLibrary
    @State private var plugins = PluginLibrary()
    @State private var homebrew = HomebrewLibrary()
    @State private var helper = HelperModel()
    @State private var updater = PeelUpdater()
    @State private var home = HomeModel()
    @State private var history: RemovalHistoryStore
    @State private var outcome: RemovalOutcome
    @State private var intel = IntelLibrary()
    @State private var space: SpaceLibrary
    @State private var carrier: SelectionCarrier
    @State private var background = StandingWork()
    @State private var textEditing = TextEditing()
    @State private var sheetInFront = SheetInFront()
    @State private var hasLaunched = false
    private let exclusions = ExclusionsStore.shared

    /// Sets the notification delegate before launch finishes, which `UNUserNotificationCenter.h` requires for
    /// clicks on notifications to reach it. A view's task can run later than that. The storage tools are made here
    /// too, so the carrier of their selection reads the same libraries their pages show.
    init() {
        SettingsKey.showInMenuBarAsBefore()
        SettingsKey.keepSidebarChoicesAsBefore()
        let notifications = PeelNotifications()
        notifications.activate()
        _notifications = State(initialValue: notifications)

        let (library, history, outcome) = (AppLibrary(), RemovalHistoryStore(), RemovalOutcome())
        let (orphans, space, developer, projects) = (
            OrphanLibrary(), SpaceLibrary(), DeveloperLibrary(), ProjectLibrary()
        )
        let (installers, duplicates, fileSearch) = (InstallerLibrary(), DuplicateLibrary(), FileSearchLibrary())
        _library = State(initialValue: library)
        _history = State(initialValue: history)
        _outcome = State(initialValue: outcome)
        _orphans = State(initialValue: orphans)
        _space = State(initialValue: space)
        _developer = State(initialValue: developer)
        _projects = State(initialValue: projects)
        _installers = State(initialValue: installers)
        _duplicates = State(initialValue: duplicates)
        _fileSearch = State(initialValue: fileSearch)
        _carrier = State(initialValue: SelectionCarrier(
            tools: [
                .orphans: orphans,
                .space: space,
                .developer: developer,
                .projects: projects,
                .installers: installers,
                .duplicates: duplicates,
                .fileSearch: fileSearch,
            ],
            apps: library,
            history: history,
            outcome: outcome
        ))
    }

    /// Keeps what Space selects in step with the helper whichever page is open, since its selection travels to the
    /// other storage pages.
    private func followHelper() async {
        for await canAct in Observations({ helper.canAct }) {
            space.follow(canUseHelper: canAct)
        }
    }

    /// Tells the Trash watch where the listed apps are, so it watches the Trash of each other disk they are on.
    private func followAppsForTheTrash() async {
        for await _ in Observations({ library.revision }) {
            trashMonitor.follow(appsAt: library.apps.map(\.url))
        }
    }

    /// Keeps the app list current as apps are installed and removed while Peel is open, and as folders are added to
    /// or removed from the ones it looks in.
    private func followFolders() async {
        var watch: Task<Void, Never>?
        defer { watch?.cancel() }
        for await folders in Observations({ library.folders }) {
            let foldersChanged = watch != nil
            watch?.cancel()
            watch = Task {
                await followApps(in: AppCatalog.directories(adding: folders ?? []), readingNow: foldersChanged)
            }
        }
    }

    private func followApps(in folders: [URL], readingNow: Bool) async {
        if readingNow {
            await appsMayHaveChanged()
        }
        for await _ in FolderWatch.changes(in: folders) {
            try? await Task.sleep(for: .seconds(1), tolerance: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await appsMayHaveChanged()
        }
    }

    private func appsMayHaveChanged() async {
        let before = library.revision
        let changed = await library.refresh()
        // Any write inside a bundle wakes the watch, so Homebrew and the rest run only when the app list changed.
        guard library.revision != before else { return }
        Task { await IconCache.warm(library.apps.map(\.url)) }
        await homebrew.refresh()
        // A newly installed app may match a cask Homebrew knows about, so the known casks are read again.
        await homebrew.loadKnownCasks(for: library.apps)
        library.loadHomebrewCasks(homebrew.caskEvidence, knowsItsOwnApps: homebrew.knowsItsOwnApps)
        // A bundle that changed on disk is a different build, and what was cached about it describes the old
        // one. Those apps are checked again at once, whoever updated them: Peel, the Homebrew page, or
        // `brew upgrade` in Terminal.
        await library.checkAgain(changed)
        // A newly installed app has never been checked, so it is due. The round checks only the apps that
        // are due.
        if checksForAppUpdates {
            await checkForUpdates()
        }
    }

    /// Looks again, each time Peel comes forward, at what may have changed while another app was in front. A
    /// window's scene phase is no sign of that: on macOS a window stays active while another app is in front.
    private func followActivations() async {
        for await _ in NotificationCenter.default.notifications(named: NSApplication.didBecomeActiveNotification) {
            guard !Task.isCancelled else { return }
            // `peel exclusions` may have changed the list while another app was in front.
            Task { await exclusions.load() }
            // History may have become readable again meanwhile, or stopped being, and `peel` may have moved something.
            history.checkReadability()
            stats.reload()
            homebrew.checkInstalled()
            // Home's checks run again whatever page is showing: permissions change in System Settings, and the
            // badge on Home in the sidebar shows a missing one. They read the helper's status again too.
            Task { await home.refresh(helper: helper) }
            Task {
                // Whichever read finds a changed bundle checks it again. When two reads overlap, only the newer
                // one reports what changed, and it may be this one rather than the folder watcher's.
                await library.checkAgain(await library.refreshUnlessRecent())
            }
            // A watch that could not start, for want of Full Disk Access or for any other reason, is tried again.
            if watchesTrash, trashMonitor.status != .watching {
                trashMonitor.start()
            }
        }
    }

    /// Records what each tool finds, its page open or not, so Home can list it. Each tool is followed on its own, so
    /// one that looks again leaves the others' dates as they were.
    private func followFindings() async {
        let tools: [(Tool, @MainActor @Sendable () -> Looked?)] = [
            (.applications, { [library] in library.looked }),
            (.orphans, { [orphans] in orphans.looked }),
            (.intel, { [intel] in intel.looked }),
            (.homebrew, { [homebrew] in homebrew.looked }),
            (.space, { [space] in space.looked }),
            (.developer, { [developer] in developer.looked }),
            (.projects, { [projects] in projects.looked }),
            (.installers, { [installers] in installers.looked }),
            (.duplicates, { [duplicates] in duplicates.looked }),
            (.cloud, { [cloud] in cloud.looked }),
        ]
        await withDiscardingTaskGroup { group in
            for (tool, looked) in tools {
                group.addTask { await follow(tool, looked) }
            }
        }
    }

    private func follow(_ tool: Tool, _ looked: @escaping @MainActor @Sendable () -> Looked?) async {
        for await value in Observations(looked) {
            guard !Task.isCancelled else { return }
            if let value {
                found.record(value, for: tool)
            }
        }
    }

    /// Runs the update round every hour while update checks are on. Each app's schedule decides whether the round
    /// checks it.
    private func askWhenDue() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(Self.updateCheckInterval), tolerance: .seconds(60))
            guard !Task.isCancelled, checksForAppUpdates else { continue }
            await checkForUpdates()
        }
    }

    private func watchFreeSpace() async {
        while !Task.isCancelled {
            if warnsWhenDiskIsNearlyFull {
                await checkFreeSpace()
            }
            try? await Task.sleep(for: .seconds(Self.freeSpaceCheckInterval), tolerance: .seconds(60))
        }
    }

    private func checkFreeSpace() async {
        let storage = await LowDiskSpace.storage()
        let defaults = UserDefaults.standard
        let told = defaults.bool(forKey: SettingsKey.toldDiskIsNearlyFull)
        let answer = LowDiskSpace.check(storage, told: told)
        // Written only when it changes: every write to the defaults makes each `AppStorage` in the app read again.
        if answer.told != told {
            defaults.set(answer.told, forKey: SettingsKey.toldDiskIsNearlyFull)
        }
        if answer.tell {
            notifications.notify(diskNearlyFull: storage)
        }
    }

    /// Starts what Peel does from launch to quit, from whichever shows first: the main window, or the menu bar item.
    /// Each piece starts once, and none is a child of the view that called it, so closing the window stops nothing.
    private func start() {
        #if DEBUG
        // A render or an export only draws and quits, so it contacts nothing and writes nothing of Peel's.
        guard HomeSnapshot.directory == nil, TerminalExport.directory == nil else { return }
        #endif
        Navigator.shared.openWindow = openWindow
        background.start([
            followFolders, followAppsForTheTrash, askWhenDue, followFindings, followActivations, watchFreeSpace,
            followHelper,
        ])
        textEditing.start()
        sheetInFront.start()
        // Work for Peel coming forward is in `followActivations`.
        guard !hasLaunched else { return }
        hasLaunched = true
        updater.start()
        Task { await launch() }
    }

    /// Loads what every page needs once, at launch: the exclusions, the apps, Homebrew, and Home's checks.
    private func launch() async {
        history.stats = stats
        history.checkReadability()
        Task { await stats.takeInEarlierTotals() }
        // Read beside the rest and behind nothing: until the exclusions are read, nothing moves.
        async let exclusionsRead: Void = Marks.interval("Exclusions") { await exclusions.load() }
        // The apps and Homebrew don't depend on Home's checks, so they load in parallel with them.
        async let homebrewPackages: Void = Marks.interval("Homebrew") { await homebrew.refresh() }
        async let apps: Void = Marks.interval("Applications") { await library.load() }
        // Home's checks run at launch, whichever page opens first. They ask the helper whether it can act,
        // which every page reads to lock the rows that need it.
        await Marks.interval("Home checks") { await home.refresh(helper: helper) }
        await exclusionsRead
        trashMonitor.onApplicationTrashed = { [notifications] url in
            notifications.notify(applicationTrashed: url)
        }
        if watchesTrash {
            trashMonitor.start()
        }
        await apps
        Task { await IconCache.warm(library.apps.map(\.url)) }
        await homebrewPackages
        await Marks.interval("Known casks") { await homebrew.loadKnownCasks(for: library.apps) }
        library.loadHomebrewCasks(homebrew.caskEvidence, knowsItsOwnApps: homebrew.knowsItsOwnApps)
        await Marks.interval("Signing teams") { await library.checkSigningTeams() }
        if checksForAppUpdates {
            await Marks.interval("Update checks") { await checkForUpdates() }
        }
    }

    /// Checks the apps that are due, and posts one notification when updates appear that were not waiting before.
    private func checkForUpdates() async {
        let before = Set(library.appsWithUpdates.map(\.id))
        await library.checkForUpdates(library.apps)
        let found = library.appsWithUpdates.filter { !before.contains($0.id) }
        guard !found.isEmpty else { return }
        notifications.notify(updatesAvailable: found.count, firstName: found[0].name, firstApp: found[0].url)
    }

    /// Whether the menu bar item shows. `MenuBarExtra` writes it back at every scene update, and each write to an
    /// `AppStorage` makes every `AppStorage` in the app read again, so a write of the value it holds is left out.
    private var menuBarItemIsInserted: Binding<Bool> {
        Binding {
            showsInMenuBar
        } set: { isInserted in
            if isInserted != showsInMenuBar { showsInMenuBar = isInserted }
        }
    }

    var body: some Scene {
        Window("Peel", id: Self.mainWindowID) {
            ContentView()
                // Above every page, because removing an app takes its page away, along with any alert attached to it.
                .removalFailureAlert()
                .alert("Peel couldn’t reopen itself", isPresented: $home.couldNotRelaunch) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text("Quit Peel and open it again, so it can use Full Disk Access.")
                }
                // Every bordered button is a capsule, the shape Liquid Glass gives the system's own controls.
                .buttonBorderShape(.capsule)
                .environment(outcome)
                .environment(stats)
                .environment(found)
                .environment(library)
                .environment(updater)
                .environment(orphans)
                .environment(projects)
                .environment(installers)
                .environment(tweaks)
                .environment(terminal)
                .environment(shell)
                .environment(git)
                .environment(ssh)
                .environment(terminalTools)
                .environment(extensions)
                .environment(cloud)
                .environment(backgroundItems)
                .environment(packages)
                .environment(developer)
                .environment(duplicates)
                .environment(fileSearch)
                .environment(plugins)
                .environment(homebrew)
                .environment(helper)
                .environment(home)
                .environment(history)
                .environment(intel)
                .environment(background)
                .environment(space)
                .environment(carrier)
                .environment(exclusions)
                // Settings also open from the sidebar, so this window needs everything they read, `trashMonitor` too.
                .environment(trashMonitor)
                .environment(\.notifications, notifications)
                .task {
                    #if DEBUG
                    Tweak.checkWords()
                    SpaceItem.checkWords()
                    AppExtension.checkWords()
                    FixedSentence.checkWords()
                    await HomeSnapshot.runIfRequested()
                    TerminalExport.runIfRequested()
                    #endif
                    start()
                }
        }
        .defaultSize(width: 1120, height: 764)
        .commands {
            PeelCommands(
                library: library, updater: updater, homebrew: homebrew, textEditing: textEditing,
                sheetInFront: sheetInFront
            )
        }
        .onChange(of: watchesTrash) { _, isWatching in
            if isWatching {
                trashMonitor.start()
                Task { await notifications.requestAuthorization() }
            } else {
                trashMonitor.stop()
            }
        }
        .onChange(of: showsInMenuBar) { _, shows in
            if !shows, !NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeMain }) {
                QuitGuard.quit()
            }
        }
        .onChange(of: warnsWhenDiskIsNearlyFull) { _, warns in
            // Turned on again, the warning is new: a disk that is already nearly full is told about at once.
            UserDefaults.standard.removeObject(forKey: SettingsKey.toldDiskIsNearlyFull)
            guard warns else { return }
            Task {
                await notifications.requestAuthorization()
                await checkFreeSpace()
            }
        }

        MenuBarExtra(isInserted: menuBarItemIsInserted) {
            MenuBarPanel()
                .environment(library)
                .environment(homebrew)
                .environment(stats)
                .environment(found)
        } label: {
            // The update count sits next to the glyph, so updates show without opening Peel.
            let count = library.menuBarUpdateCount
            HStack(spacing: 3) {
                Image(.peelGlyph)
                if count > 0 {
                    // Monospaced digits keep the width steady between counts with the same number of digits. The
                    // menu bar lays out from the right, so a change in width would shift every item to its left.
                    Text(count, format: .number)
                        .monospacedDigit()
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(count == 0 ? Text("Peel") : Text("Peel, ^[\(count) update](inflect: true) waiting"))
            // A launch that restores no window shows only this item, while Peel shows in the menu bar.
            .task { start() }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .buttonBorderShape(.capsule)
                .environment(helper)
                .environment(trashMonitor)
                .environment(exclusions)
                .environment(library)
                .environment(homebrew)
                .environment(history)
                .environment(home)
                .environment(background)
                .environment(orphans)
        }
        .windowResizability(.contentSize)

        Window(Text(AboutView.title), id: AboutView.windowID) {
            AboutView()
                .environment(updater)
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .restorationBehavior(.disabled)
        .defaultPosition(.center)
    }
}
