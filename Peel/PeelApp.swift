import PeelCore
import SwiftUI

/// Decides whether Peel quits when its window closes. SwiftUI's documentation for `Window` says an app whose
/// primary scene is a single window quits when that window closes. Peel keeps running in the menu bar while it
/// watches the Trash, so it quits only when that setting is off.
@MainActor
final class PeelAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ application: NSApplication) -> Bool {
        !UserDefaults.standard.bool(forKey: SettingsKey.watchesTrash)
    }
}

@main
struct PeelApp: App {
    @NSApplicationDelegateAdaptor(PeelAppDelegate.self) private var delegate
    @Environment(\.scenePhase) private var scenePhase
    static let mainWindowID = "main"
    /// How often the update round runs. The shortest wait an app can have is six hours, after a failed check
    /// (`UpdateSchedule.afterFailure`), so an hourly round checks each app soon after it is due.
    private static let updateCheckInterval: TimeInterval = 60 * 60

    @AppStorage(SettingsKey.checksForAppUpdates) private var checksForAppUpdates = true
    @AppStorage(SettingsKey.watchesTrash) private var watchesTrash = false
    @State private var trashMonitor = TrashMonitor()
    @State private var notifications: PeelNotifications
    @State private var stats = LifetimeStats()
    @State private var found = FoundLastTimeStore()
    @State private var library = AppLibrary()
    @State private var orphans = OrphanLibrary()
    @State private var projects = ProjectLibrary()
    @State private var installers = InstallerLibrary()
    @State private var tweaks = TweakLibrary()
    @State private var extensions = ExtensionLibrary()
    @State private var cloud = CloudLibrary()
    @State private var backgroundItems = BackgroundItemLibrary()
    @State private var packages = PackageLibrary()
    @State private var developer = DeveloperLibrary()
    @State private var duplicates = DuplicateLibrary()
    @State private var fileSearch = FileSearchLibrary()
    @State private var plugins = PluginLibrary()
    @State private var homebrew = HomebrewLibrary()
    @State private var helper = HelperModel()
    @State private var home = HomeModel()
    @State private var history = RemovalHistoryStore()
    @State private var outcome = RemovalOutcome()
    @State private var intel = IntelLibrary()
    @State private var space = SpaceLibrary()
    @State private var background = BackgroundWork()
    @State private var hasLaunched = false
    private let exclusions = ExclusionsStore.shared

    /// Sets the notification delegate before launch finishes, which `UNUserNotificationCenter.h` requires for
    /// clicks on notifications to reach it. A view's task can run later than that.
    init() {
        let notifications = PeelNotifications()
        notifications.activate()
        _notifications = State(initialValue: notifications)
    }

    /// Keeps the app list current as apps are installed and removed while Peel is open.
    private func followFolders() async {
        for await _ in FolderWatch.changes(in: AppCatalog.defaultDirectories) {
            try? await Task.sleep(for: .seconds(1), tolerance: .milliseconds(250))
            let before = library.revision
            let changed = await library.refresh()
            // Any write inside a bundle wakes this loop, so Homebrew and the rest run only when the app list changed.
            guard library.revision != before else { continue }
            Task { await IconCache.warm(library.apps.map(\.url)) }
            await homebrew.refresh()
            // A newly installed app may match a cask Homebrew knows about, so the known casks are read again.
            await homebrew.loadKnownCasks(for: library.apps)
            library.loadHomebrewCasks(homebrew.caskEvidence)
            // A bundle that changed on disk is a different build, and what was cached about it describes the old
            // one. Those apps are checked again at once, whoever updated them: Peel, the Homebrew page, or
            // `brew upgrade` in Terminal.
            if checksForAppUpdates, !changed.isEmpty {
                await library.checkForUpdates(changed, force: true)
            }
            // A new build may be signed by a different team.
            if !changed.isEmpty {
                await library.checkSigningTeams()
            }
            // A newly installed app has never been checked, so it is due. The round checks only the apps that
            // are due.
            if checksForAppUpdates {
                await checkForUpdates()
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
            watchesTrash
        } set: { isInserted in
            if isInserted != watchesTrash { watchesTrash = isInserted }
        }
    }

    var body: some Scene {
        Window("Peel", id: Self.mainWindowID) {
            ContentView()
                // Above every page, because removing an app takes its page away, along with any alert attached to it.
                .removalFailureAlert()
                // Every bordered button is a capsule, the shape Liquid Glass gives the system's own controls.
                .buttonBorderShape(.capsule)
                .environment(outcome)
                .environment(stats)
                .environment(found)
                .environment(library)
                .environment(orphans)
                .environment(projects)
                .environment(installers)
                .environment(tweaks)
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
                .environment(space)
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
                    #endif
                    // While Peel watches the Trash it keeps running after its window closes, so reopening the window
                    // must not run the launch work again. Work for a window coming forward is in `scenePhase` below.
                    guard !hasLaunched else { return }
                    hasLaunched = true
                    history.stats = stats
                    // The apps and Homebrew don't depend on Home's checks, so they load in parallel with them.
                    async let homebrewPackages: Void = Marks.interval("Homebrew") { await homebrew.refresh() }
                    async let apps: Void = Marks.interval("Applications") { await library.load() }
                    // Home's checks run at launch, whichever page opens first. They ask the helper whether it can act,
                    // which every page reads to lock the rows that need it.
                    await Marks.interval("Home checks") { await home.refresh(helper: helper) }
                    await Marks.interval("Exclusions") { await exclusions.load() }
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
                    library.loadHomebrewCasks(homebrew.caskEvidence)
                    await Marks.interval("Signing teams") { await library.checkSigningTeams() }
                    if checksForAppUpdates {
                        await Marks.interval("Update checks") { await checkForUpdates() }
                    }
                }
                .task {
                    // Started once, and not as a child of this view's task, so the work goes on in the menu bar
                    // after the window closes.
                    background.start([followFolders, askWhenDue, followFindings])
                }
        }
        .defaultSize(width: 1120, height: 764)
        .commands {
            PeelCommands(library: library, homebrew: homebrew)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                helper.refresh()
                // Home's checks run again whatever page is showing: permissions change in System Settings, and the
                // badge on Home in the sidebar shows a missing one.
                Task { await home.refresh(helper: helper) }
                Task {
                    // Whichever read finds a changed bundle checks it again. When two reads overlap, only the newer
                    // one reports what changed, and it may be this one rather than the folder watcher's.
                    let changed = await library.refreshUnlessRecent()
                    if checksForAppUpdates, !changed.isEmpty {
                        await library.checkForUpdates(changed, force: true)
                    }
                    if !changed.isEmpty {
                        await library.checkSigningTeams()
                    }
                }
                if watchesTrash, trashMonitor.status == .needsFullDiskAccess {
                    trashMonitor.start()
                }
            }
        }
        .onChange(of: watchesTrash) { _, isWatching in
            if isWatching {
                trashMonitor.start()
                Task { await notifications.requestAuthorization() }
            } else {
                trashMonitor.stop()
            }
        }

        MenuBarExtra(isInserted: menuBarItemIsInserted) {
            MenuBarPanel()
                .environment(library)
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
        }
        .windowResizability(.contentSize)

        Window(Text(AboutView.title), id: AboutView.windowID) {
            AboutView()
                .environment(library)
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .restorationBehavior(.disabled)
        .defaultPosition(.center)
    }
}
