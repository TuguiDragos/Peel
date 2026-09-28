import Foundation
import Observation
import PeelCore

enum AppSort: String, CaseIterable, Identifiable {
    case name
    case size
    case lastOpened
    case dateAdded

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .name: "Name"
        case .size: "Size"
        case .lastOpened: "Last Opened"
        case .dateAdded: "Date Added"
        }
    }
}

enum AppSource: String, CaseIterable, Identifiable {
    case appStore
    case homebrew
    case setapp
    case direct

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .appStore: "App Store"
        case .homebrew: "Homebrew"
        case .setapp: LocalizedStringResource("Setapp", comment: "A product's name, never translated.")
        case .direct: "Downloaded"
        }
    }
}

/// The apps the Applications list shows: those with an update waiting, drawn first, and the rest.
struct VisibleApps {
    let waiting: [InstalledApp]
    let rest: [InstalledApp]

    var isEmpty: Bool { waiting.isEmpty && rest.isEmpty }
}

private enum UpdateMemoryStore {
    static func load() -> [String: UpdateMemory] {
        guard let data = UserDefaults.standard.data(forKey: SettingsKey.updateMemory) else { return [:] }
        return (try? JSONDecoder().decode([String: UpdateMemory].self, from: data)) ?? [:]
    }

    static func save(_ memory: [String: UpdateMemory]) {
        guard let data = try? JSONEncoder().encode(memory) else { return }
        UserDefaults.standard.set(data, forKey: SettingsKey.updateMemory)
    }
}

@Observable
final class AppLibrary {
    private static let concurrentUpdateChecks = 6
    private static let concurrentSizeReads = 4
    /// The number of months without being opened after which an app counts as unused.
    static let unusedMonths = 6

    private(set) var apps: [InstalledApp] = []
    /// Incremented whenever the apps listed change: one installed, removed, moved, or replaced by another build.
    /// Work is keyed to this rather than to `apps.count`, because an upgrade replaces a bundle without changing the
    /// count. When an app was last opened is not part of it, since opening an app changes nothing that is installed.
    private(set) var revision = 0
    /// Incremented when only the dates the apps were last opened changed, which the list shows, sorts by, and
    /// filters on.
    private(set) var lastOpenedRevision = 0
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    /// The folders the person chose for apps, beside the Applications folders. `PeelApp` watches them and reads the
    /// apps again when they change.
    private(set) var folders = AppFolders().load()
    private(set) var couldNotSaveFolders = false
    private(set) var updateStatuses: [InstalledApp.ID: UpdateStatus] = [:] {
        didSet { updatesRevision += 1 }
    }

    /// Incremented by anything that changes which apps have an update waiting, so the list redraws.
    private(set) var updatesRevision = 0
    private var updateRounds = UpdateRounds<InstalledApp.ID>() {
        didSet {
            if updateRounds.checking.isEmpty {
                heldUpdateCount = nil
            } else if oldValue.checking.isEmpty {
                heldUpdateCount = appsWithUpdates.count
            }
        }
    }
    var appsCheckingForUpdates: Set<InstalledApp.ID> { updateRounds.checking }
    /// The update count when the current round of checks began. The menu bar shows it until the round ends,
    /// rather than a count that climbs as answers arrive seconds apart.
    private var heldUpdateCount: Int?
    private(set) var sizes: [InstalledApp.ID: Int64] = [:] {
        didSet { sizesRevision += 1 }
    }
    /// The apps whose bundle could not be measured, by time or by macOS, so their size is not known rather than
    /// still to come. The list reads "Unknown" for them and sorts them first.
    private(set) var unmeasured: Set<InstalledApp.ID> = [] {
        didSet { sizesRevision += 1 }
    }

    /// Incremented when a size arrives. Only the size sort depends on it, so other sorts keep their cached list.
    private(set) var sizesRevision = 0
    private(set) var lastUpdateChecks: [InstalledApp.ID: Date] = [:]
    /// Apps whose signing team changed without the user acknowledging it yet, by bundle identifier.
    private(set) var teamChanges: [String: TeamRegistry.Change] = [:]
    /// Why the record of who signs each app is not being kept, or nil while it is.
    private(set) var teamRecordProblem: TeamRegistry.Problem?
    /// The casks Homebrew knows, installed or not, for telling where an app came from and comparing versions.
    private(set) var casks: [HomebrewPackage] = []
    /// The cask each Homebrew-installed app came from. Matched with the same evidence everything else uses,
    /// rather than by guessing a token from the app's name.
    private(set) var homebrewApps: [InstalledApp.ID: HomebrewPackage] = [:]
    /// The rows chosen in the list, which the page beside it shows.
    var selection: Set<InstalledApp.ID> = []
    /// The apps selected with their checkboxes, to be removed together. Kept apart from `selection`, so
    /// choosing a row to look at never clears the batch.
    var picked: Set<InstalledApp.ID> = []
    private(set) var ignoredIdentifiers = Set(UserDefaults.standard.stringArray(forKey: SettingsKey.ignoredUpdateApps) ?? []) {
        didSet { updatesRevision += 1 }
    }

    private(set) var skippedVersions = UserDefaults.standard.dictionary(forKey: SettingsKey.skippedUpdateVersions) as? [String: String] ?? [:] {
        didSet { updatesRevision += 1 }
    }
    var sort = AppSort.name
    var sources: Set<AppSource> = []
    /// The developer whose apps the list shows, or nil for all developers.
    var selectedDeveloper: String?
    var showsOnlyUnused = false
    /// True when any of the list's filters is on, the same three `visible(matching:)` applies.
    var isFiltering: Bool { !sources.isEmpty || selectedDeveloper != nil || showsOnlyUnused }

    private var memory = UpdateMemoryStore.load()
    /// Apps shown from outside the scanned folders, such as one in Downloads or in the Trash. Kept apart,
    /// because the next reading of the folders doesn't find them and would drop their row and their page.
    private var revealed: [InstalledApp] = []
    /// The listed apps that are in a Trash, which only a revealed one can be: Watch the Trash leads to them so what
    /// they left behind can go. They are on their way out, so no round checks them, and no update is counted.
    private var appsInATrash: Set<InstalledApp.ID> = []
    /// Runs the reading of the folders. A new reading stops one still running, since the older one could
    /// finish last with a list that lacks an app installed in between.
    let scanRun = ScanRun()
    private var lastRead: ContinuousClock.Instant?
    private let updateChecker = UpdateChecker()
    private let teamRegistry = TeamRegistry()

    /// The apps the page beside the list shows: the chosen rows, or the selected batch when no row is chosen.
    private var shown: Set<InstalledApp.ID> {
        selection.isEmpty ? picked : selection
    }

    var selectedApp: InstalledApp? {
        shown.count == 1 ? apps.first { shown.contains($0.id) } : nil
    }

    var selectedApps: [InstalledApp] {
        apps.filter { shown.contains($0.id) }
    }

    var isShowingSeveral: Bool {
        shown.count > 1
    }

    func load() async {
        isLoading = true
        lastRead = .now
        let found = await AppCatalog.installedApps()
        adopt(found)
        recall()
        isLoading = false
        hasLoaded = true
        await AppMemory().remember(found)
    }

    /// Calls `refresh()` unless the folders were read in the last 30 seconds. For Peel coming forward:
    /// the folder watcher sees every real change, so a recent read is enough.
    func refreshUnlessRecent() async -> [InstalledApp] {
        if let lastRead, ContinuousClock.now - lastRead < .seconds(30) { return [] }
        return await refresh()
    }

    func addFolders(_ urls: [URL]) {
        changeFolders { $0.add(urls) }
    }

    func removeFolders(_ urls: [URL]) {
        changeFolders { $0.remove(urls) }
    }

    private func changeFolders(_ change: (AppFolders) -> Bool) {
        let store = AppFolders()
        couldNotSaveFolders = !change(store)
        folders = store.load()
    }

    /// Reads the folders again without emptying the list first, so an app installed while Peel is open
    /// appears in its place instead of the whole list blinking.
    ///
    /// Returns the apps whose build changed, so the caller can check them again. An upgrade keeps the path,
    /// and with it the app's identity, so what was cached about the old build (its size, its update status,
    /// when it was last checked) is dropped rather than shown for a version it doesn't describe.
    @discardableResult
    func refresh() async -> [InstalledApp] {
        guard let found = await scanRun.run({ await AppCatalog.installedApps() }) else { return [] }
        lastRead = .now
        let listed = AppCatalog.sorted(found + stillThere(revealed, beside: found))
        guard listed != apps else { return [] }
        guard !AppCatalog.listsTheSameApps(listed, as: apps) else {
            apps = listed
            lastOpenedRevision += 1
            return []
        }
        let changed = adopt(found)
        // Remembered whenever the list changes, so an app installed and removed between two visits to Orphaned
        // Files is still known. Done last, so nothing above is left half done while this waits.
        await AppMemory().remember(found)
        return changed
    }

    /// Takes a new reading of the folders and returns the apps whose build changed. Drops whatever was cached
    /// about an app that is gone or a build that was replaced, so an app removed and installed again never
    /// shows the old copy's size or update status. Both `load()` and `refresh()` come through here.
    @discardableResult
    private func adopt(_ found: [InstalledApp]) -> [InstalledApp] {
        revealed = stillThere(revealed, beside: found)
        let trash = TrashService()
        appsInATrash = Set(revealed.filter { trash.isInsideATrash($0.url) }.map(\.id))
        let listed = AppCatalog.sorted(found + revealed)
        let previous = Dictionary(apps.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let changed = listed.filter { app in previous[app.id].map { !Self.isTheSameBuild($0, app) } ?? false }
        apps = listed
        revision += 1
        matchHomebrewApps()

        let present = Set(listed.map(\.id))
        let stale = Set(changed.map(\.id))
        let keeps = { (id: InstalledApp.ID) in present.contains(id) && !stale.contains(id) }
        sizes = sizes.filter { keeps($0.key) }
        unmeasured = unmeasured.filter(keeps)
        updateStatuses = updateStatuses.filter { keeps($0.key) }
        lastUpdateChecks = lastUpdateChecks.filter { keeps($0.key) }
        selection.formIntersection(present)
        picked.formIntersection(present)

        // Forgets what was learned about a build that was replaced, including when to check it again.
        let recalled = UpdateMemory.recalled(from: memory, for: listed)
        if recalled != memory {
            memory = recalled
            UpdateMemoryStore.save(memory)
        }
        return changed
    }

    /// The revealed apps that are still on disk and that the new reading of the folders did not find.
    private func stillThere(_ revealed: [InstalledApp], beside found: [InstalledApp]) -> [InstalledApp] {
        let listed = Set(found.map(\.id))
        return revealed.filter { !listed.contains($0.id) && FileManager.default.fileExists(atPath: $0.url.path(percentEncoded: false)) }
    }

    /// Restores the update answers saved by earlier runs, for apps still at the build they describe.
    private func recall() {
        for app in apps {
            guard let remembered = memory[app.bundleIdentifier], remembered.describes(app) else { continue }
            updateStatuses[app.id] = remembered.status
            if let checked = remembered.checked {
                lastUpdateChecks[app.id] = checked
            }
        }
    }

    /// Whether two readings of the same path are the same build. Deliberately not `==`: `lastUsedDate`
    /// changes every time an app is opened, which is no reason to forget its size or check for updates again.
    private static func isTheSameBuild(_ before: InstalledApp, _ after: InstalledApp) -> Bool {
        before.version == after.version
            && before.buildVersion == after.buildVersion
            && before.architectures == after.architectures
            && before.teamIdentifier == after.teamIdentifier
    }

    /// Measures the apps with no size yet. Each bundle needs a walk of every file, so sizes arrive after the list.
    /// A bundle that could not be measured is asked once more after `remeasureDelay`: a walk that ran out of time
    /// goes on, and its answer is kept for the next question.
    func loadSizes() async {
        await measure(apps.filter { sizes[$0.id] == nil })
        guard !unmeasured.isEmpty, (try? await Task.sleep(for: Self.remeasureDelay)) != nil else { return }
        await measure(apps.filter { unmeasured.contains($0.id) })
    }

    private static let remeasureDelay = Duration.seconds(30)

    private func measure(_ missing: [InstalledApp]) async {
        guard !missing.isEmpty else { return }
        let measured = Dictionary(missing.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        await withTaskGroup(of: (InstalledApp.ID, Int64?).self) { group in
            var pending = missing.makeIterator()
            for _ in 0..<Self.concurrentSizeReads {
                guard let app = pending.next() else { break }
                _ = group.addTaskUnlessCancelled { (app.id, await FileSize.reclaimableSize(of: app.url)) }
            }
            while let (id, size) = await group.next() {
                // A walk given up because the list changed says nothing about the bundle, and a bundle replaced
                // while it was walked is another build, so neither answer is kept.
                if !Task.isCancelled, let app = measured[id], apps.contains(where: { $0.id == id && Self.isTheSameBuild($0, app) }) {
                    if let size {
                        sizes[id] = size
                        unmeasured.remove(id)
                    } else {
                        unmeasured.insert(id)
                    }
                }
                if !Task.isCancelled, let app = pending.next() {
                    _ = group.addTaskUnlessCancelled { (app.id, await FileSize.reclaimableSize(of: app.url)) }
                }
            }
        }
    }

    func source(of app: InstalledApp) -> AppSource {
        if app.isFromAppStore { return .appStore }
        if app.isFromSetapp { return .setapp }
        return homebrewApps[app.id] != nil ? .homebrew : .direct
    }

    /// The app's developer. The signature names it for a Developer ID app or one of Apple's. An App Store app,
    /// which Apple signs again, takes the name from another installed app of its team, or else the name the
    /// App Store gave at the last update check.
    func developer(of app: InstalledApp) -> String? {
        app.developer ?? app.teamIdentifier.flatMap { developersByTeam[$0] } ?? memory[app.bundleIdentifier]?.developer
    }

    /// The developers with two or more apps, for the list's filter. A developer with one app is left out to
    /// keep the menu short, and search finds that app by its developer anyway. The chosen developer stays
    /// listed even when none of its apps remain, since it is what empties the list.
    var developers: [String] {
        let counts = Dictionary(apps.compactMap(developer(of:)).map { ($0, 1) }, uniquingKeysWith: +)
        return Set(counts.filter { $0.value > 1 }.map(\.key) + [selectedDeveloper].compactMap(\.self))
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private var developersByTeam: [String: String] {
        if let lastTeams, lastTeams.revision == revision { return lastTeams.names }
        let names = Dictionary(
            apps.compactMap { app in app.developer.flatMap { name in app.teamIdentifier.map { ($0, name) } } },
            uniquingKeysWith: { first, _ in first }
        )
        lastTeams = (revision, names)
        return names
    }

    /// The cask this app was installed from, which is the name `brew upgrade` has to be given.
    func cask(for app: InstalledApp) -> HomebrewPackage? {
        homebrewApps[app.id]
    }

    func isUnused(_ app: InstalledApp) -> Bool {
        AppOrder.isUnused(app, forMonths: Self.unusedMonths)
    }

    /// The last answer of `visibleApps(matching:)`. This and the caches below are written while a view's
    /// body is evaluated, so they are kept out of Observation: a change there would trigger another update.
    @ObservationIgnored private var lastVisible: (key: VisibleKey, apps: VisibleApps)?
    @ObservationIgnored private var lastExcluded: (revision: Int, exclusions: Exclusions, ids: Set<InstalledApp.ID>)?
    @ObservationIgnored private var lastNames: (revision: Int, names: [String: String])?
    @ObservationIgnored private var lastTeams: (revision: Int, names: [String: String])?

    /// The apps the user excluded. Worked out again only when the apps or the exclusions change, since each
    /// check resolves the app's path on disk.
    func excludedIDs(by exclusions: Exclusions) -> Set<InstalledApp.ID> {
        if let lastExcluded, lastExcluded.revision == revision, lastExcluded.exclusions == exclusions { return lastExcluded.ids }
        let ids = Set(apps.filter(exclusions.excludes).map(\.id))
        lastExcluded = (revision, exclusions, ids)
        return ids
    }

    private struct VisibleKey: Hashable {
        let revision: Int
        let lastOpened: Int
        let updates: Int
        let sizes: Int
        let sort: AppSort
        let sources: Set<AppSource>
        let developer: String?
        let showsOnlyUnused: Bool
        let searchText: String
    }

    /// The apps the list shows. Those with an update waiting are split out and drawn first, since a badge
    /// alone is easy to miss in a long list. Both parts keep the chosen sort.
    ///
    /// The answer is cached until one of its inputs changes, so a size or an update status arriving doesn't
    /// filter and sort the whole list again.
    func visibleApps(matching searchText: String) -> VisibleApps {
        let key = VisibleKey(
            revision: revision,
            lastOpened: lastOpenedRevision,
            updates: updatesRevision,
            sizes: sort == .size ? sizesRevision : 0,
            sort: sort,
            sources: sources,
            developer: selectedDeveloper,
            showsOnlyUnused: showsOnlyUnused,
            searchText: searchText
        )
        if let lastVisible, lastVisible.key == key { return lastVisible.apps }
        let answer = visible(matching: searchText)
        lastVisible = (key, answer)
        return answer
    }

    private func visible(matching searchText: String) -> VisibleApps {
        var result = apps
        if !searchText.isEmpty {
            result = result.filter {
                SearchText.matches($0.name, searchText) || SearchText.matches($0.bundleIdentifier, searchText)
                    || developer(of: $0).map { SearchText.matches($0, searchText) } == true
            }
        }
        if !sources.isEmpty {
            result = result.filter { sources.contains(source(of: $0)) }
        }
        if let selectedDeveloper {
            result = result.filter { developer(of: $0) == selectedDeveloper }
        }
        if showsOnlyUnused {
            result = result.filter(isUnused)
        }

        var waiting: [InstalledApp] = []
        var rest: [InstalledApp] = []
        for app in sorted(result) {
            if hasUpdate(app) {
                waiting.append(app)
            } else {
                rest.append(app)
            }
        }
        return VisibleApps(waiting: waiting, rest: rest)
    }

    private func sorted(_ apps: [InstalledApp]) -> [InstalledApp] {
        switch sort {
        case .name:
            apps.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .size:
            AppOrder.sortedBySize(apps, sizes: sizes, unmeasured: unmeasured)
        case .lastOpened:
            AppOrder.sorted(apps) { $0.lastUsedDate ?? .distantPast }
        case .dateAdded:
            AppOrder.sorted(apps) { $0.dateAdded ?? .distantPast }
        }
    }

    /// Checks the apps in `targets` that are due, and schedules when each is due next.
    ///
    /// `force` checks every target that isn't ignored, whatever the schedule says. It is for checks the user
    /// asked for, and for bundles that changed on disk, which are not the build the last answer described.
    func checkForUpdates(_ targets: [InstalledApp], force: Bool = false) async {
        // Read here, where every caller passes. Settings promises that with this off, Peel contacts nothing on
        // its own, so even Rescan on an app's page only rescans files.
        guard UserDefaults.standard.object(forKey: SettingsKey.checksForAppUpdates) as? Bool ?? true else { return }
        let now = Date.now
        let wanted = targets.filter { app in
            guard !isIgnored(app), !appsInATrash.contains(app.id) else { return false }
            guard !force else { return true }
            // Already being checked by another round: a second answer could double the wait for the next check.
            guard !appsCheckingForUpdates.contains(app.id) else { return false }
            return memory[app.bundleIdentifier]?.schedule.isDue(at: now) ?? true
        }
        // The list's own entry, not the caller's: a page that was open through an upgrade still holds the old build.
        .map { app in apps.first { $0.id == app.id } ?? app }
        guard !wanted.isEmpty else { return }
        let asked = Dictionary(wanted.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let round = updateRounds.begin(wanted.map(\.id))
        // However the round ends, no app is left marked as being checked by it.
        defer { updateRounds.end(round) }
        let checker = updateChecker
        let preference = updateSource
        let casks = casks

        await withTaskGroup(of: (InstalledApp.ID, UpdateAnswer).self) { group in
            var pending = wanted.makeIterator()
            for _ in 0..<Self.concurrentUpdateChecks {
                guard let app = pending.next() else { break }
                _ = group.addTaskUnlessCancelled { (app.id, await checker.answer(for: app, preference: preference, casks: casks)) }
            }
            while case let (id, answer)? = await group.next() {
                let status = answer.status
                // The update source changed since this round began, and the round that change started answers now.
                guard updateRounds.answered(id, in: round) else {
                    group.cancelAll()
                    continue
                }
                // In a canceled round every pending request ends as a failure. Recording those would erase
                // what was known and put off the next check for hours.
                guard !Task.isCancelled else { continue }
                // The answer describes the build that was asked about, which may have been replaced since.
                guard let app = asked[id], apps.contains(where: { $0.id == id && Self.isTheSameBuild($0, app) }) else { continue }
                let kept = status.following(updateStatuses[id])
                updateStatuses[id] = kept
                if status != .failed {
                    lastUpdateChecks[id] = .now
                }
                let identifier = app.bundleIdentifier
                memory[identifier] = UpdateMemory(
                    status: kept,
                    schedule: UpdateSchedule.next(after: status, following: memory[identifier]?.schedule),
                    checked: status == .failed ? memory[identifier]?.checked : .now,
                    describing: app,
                    developer: answer.developer ?? memory[identifier]?.developer
                )
                if let app = pending.next() {
                    _ = group.addTaskUnlessCancelled { (app.id, await checker.answer(for: app, preference: preference, casks: casks)) }
                }
            }
        }
        guard !Task.isCancelled, updateRounds.isCurrent(round) else { return }
        UpdateMemoryStore.save(memory)
    }

    /// The user's update settings as one value. The command line reads the same settings from the same keys,
    /// so the app and `peel` can't disagree about what is waiting.
    var updatePreferences: UpdatePreferences {
        UpdatePreferences(source: updateSource, ignoredIdentifiers: ignoredIdentifiers, skippedVersions: skippedVersions)
    }

    /// Whether an update is waiting for `app`. An ignored app has none, and neither has one whose waiting
    /// version was skipped. The list, the menu bar, and the notification all ask this, so they always agree.
    /// Peel's own is told by About instead (`newerPeel`).
    func hasUpdate(_ app: InstalledApp) -> Bool {
        !app.isPeelItself && updatePreferences.isWaiting(updateStatuses[app.id], for: app)
    }

    /// The answer about `app`'s updates that its page shows: an update the user muted is not announced again.
    func shownUpdateStatus(of app: InstalledApp) -> UpdateStatus? {
        app.isPeelItself ? nil : updatePreferences.shownStatus(updateStatuses[app.id], for: app)
    }

    /// A newer release of the copy of Peel that is running, which About tells and never installs.
    struct PeelUpdate: Equatable {
        let version: String
        /// The release's page on GitHub, where it is downloaded.
        let page: URL?
        /// The command that upgrades a copy Homebrew installed, which Peel never runs on itself.
        let homebrewCommand: String?
    }

    var newerPeel: PeelUpdate? {
        let running = PathPattern.comparablePath(of: Bundle.main.bundleURL)
        guard
            let peel = apps.first(where: { PathPattern.comparablePath(of: $0.url) == running }),
            let status = updateStatuses[peel.id], let version = status.displayVersion
        else { return nil }
        let command = status.source == .homebrew ? cask(for: peel).map { "brew upgrade --cask \($0.name)" } : nil
        return PeelUpdate(version: version, page: status.releaseNotes, homebrewCommand: command)
    }

    var appsWithUpdates: [InstalledApp] { apps.filter(hasUpdate) }

    /// The count the menu bar shows. It follows `hasUpdate(_:)`, but while a round of checks runs it keeps
    /// the count from when the round began.
    var menuBarUpdateCount: Int {
        heldUpdateCount ?? appsWithUpdates.count
    }

    var updateSource: UpdateSource {
        UpdateSource(rawValue: UserDefaults.standard.string(forKey: SettingsKey.updateSource) ?? "") ?? .automatic
    }

    /// Forgets every update answer and schedule, then checks every app again. The answers shown were found
    /// under the old source, and the badge would explain them in terms of the new one.
    func updateSourceChanged() async {
        updateRounds.sourceChanged()
        updateStatuses = [:]
        lastUpdateChecks = [:]
        memory = [:]
        UpdateMemoryStore.save(memory)
        await checkForUpdates(apps, force: true)
    }

    func isIgnored(_ app: InstalledApp) -> Bool {
        updatePreferences.isIgnored(app)
    }

    func setIgnored(_ isIgnored: Bool, for app: InstalledApp) {
        var identifiers = ignoredIdentifiers
        if isIgnored {
            identifiers.insert(app.bundleIdentifier)
        } else {
            identifiers.remove(app.bundleIdentifier)
        }
        ignoredIdentifiers = identifiers
        UserDefaults.standard.set(Array(identifiers).sorted(), forKey: SettingsKey.ignoredUpdateApps)
    }

    func skippedVersion(for app: InstalledApp) -> String? {
        skippedVersions[app.bundleIdentifier]
    }

    func skip(version: String, for app: InstalledApp) {
        skippedVersions[app.bundleIdentifier] = version
        UserDefaults.standard.set(skippedVersions, forKey: SettingsKey.skippedUpdateVersions)
    }

    /// Undoes both a skipped version and "never check this app", by identifier: what was muted may not be
    /// installed anymore, and then there is no `InstalledApp` to name it with.
    func unmute(_ identifier: String) {
        ignoredIdentifiers.remove(identifier)
        skippedVersions.removeValue(forKey: identifier)
        UserDefaults.standard.set(ignoredIdentifiers.sorted(), forKey: SettingsKey.ignoredUpdateApps)
        UserDefaults.standard.set(skippedVersions, forKey: SettingsKey.skippedUpdateVersions)
    }

    /// Called often, including every time the Applications list appears. Apps are matched to casks again only
    /// when the casks changed, since `adopt` already does it when the apps change, and matching holds the
    /// main thread.
    func loadHomebrewCasks(_ packages: [HomebrewPackage]) {
        let casks = packages.filter { $0.kind == .cask }
        if casks != self.casks {
            self.casks = casks
            matchHomebrewApps()
        }
        applyHomebrewStatuses()
    }

    /// Records an update for each app whose cask Homebrew marks outdated. Reading Homebrew costs no network
    /// request, so this doesn't wait for the update schedule, and Applications agrees with the Homebrew page.
    /// It applies only to an app with no answer of its own, or whose own check failed or had no feed to ask:
    /// an answer from the app's own feed wins.
    private func applyHomebrewStatuses() {
        for (id, cask) in homebrewApps {
            let homebrew = UpdateChecker.homebrewStatus(of: cask)
            guard case .updateAvailable = homebrew else { continue }
            let known = updateStatuses[id]
            guard known == nil || known == .failed || known == .unsupported else { continue }
            updateStatuses[id] = homebrew
        }
    }

    private func matchHomebrewApps() {
        let casks = casks
        homebrewApps = Dictionary(uniqueKeysWithValues: apps.compactMap { app in
            CaskEvidence.installedCask(for: app, in: casks).map { (app.id, $0) }
        })
    }

    /// Records the team that signs each app, and keeps the apps whose team changed. The registry reports each
    /// change again on every launch until the user acknowledges it.
    func checkSigningTeams() async {
        let outcome = await teamRegistry.check(apps)
        teamChanges = Dictionary(outcome.changes.map { ($0.bundleIdentifier, $0) }, uniquingKeysWith: { first, _ in first })
        teamRecordProblem = outcome.problem
    }

    func acknowledgeTeamChange(for app: InstalledApp) async {
        teamChanges.removeValue(forKey: app.bundleIdentifier)
        if let problem = await teamRegistry.acknowledge(app.bundleIdentifier) {
            teamRecordProblem = problem
        }
    }

    /// Keeps a record of signers that cannot be read beside a new one, and records who signs each app now.
    func startTeamRecordOver() async {
        guard await teamRegistry.startOver() else { return }
        await checkSigningTeams()
    }

    /// Selects the apps together, adding each first when it lives outside the scanned folders, for example in
    /// the Trash. What is not an app is passed over.
    func reveal(_ urls: [URL]) async {
        var chosen: Set<InstalledApp.ID> = []
        for url in urls {
            if let id = await listed(url) {
                chosen.insert(id)
            }
        }
        guard !chosen.isEmpty else { return }
        selection = chosen
    }

    private func listed(_ url: URL) async -> InstalledApp.ID? {
        let bundleURL = url.standardizedFileURL
        // Looked up on disk, since a trailing slash, another case, or a link can name a bundle already listed.
        // Listed twice, the app would be its own rival and share every file with itself.
        if let existing = await Self.find(bundleURL, among: apps) {
            return existing.id
        }
        guard bundleURL.pathExtension == "app", let app = await Self.inspect(bundleURL) else { return nil }
        // Checked again, since two drops of the same bundle can both get this far before either is listed.
        if !apps.contains(where: { $0.id == app.id }) {
            revealed.append(app)
            adopt(apps.filter { listed in !revealed.contains { $0.id == listed.id } })
        }
        return app.id
    }

    @concurrent
    nonisolated static func inspect(_ url: URL) async -> InstalledApp? {
        AppInspector.inspect(url)
    }

    @concurrent
    private nonisolated static func find(_ url: URL, among apps: [InstalledApp]) async -> InstalledApp? {
        AppCatalog.app(at: url, among: apps)
    }

    /// The name of the app with `bundleIdentifier`: the listed app's, or the one Finder shows for an app macOS knows
    /// elsewhere, such as a helper or a Nightly build on another disk. The identifier itself when macOS knows none.
    func name(forBundleIdentifier bundleIdentifier: String) -> String {
        if lastNames?.revision != revision {
            lastNames = (revision, Dictionary(apps.map { ($0.bundleIdentifier, $0.name) }, uniquingKeysWith: { first, _ in first }))
        }
        if let name = lastNames?.names[bundleIdentifier] { return name }
        let name = AppInspector.applicationURL(forBundleIdentifier: bundleIdentifier).map(AppInspector.displayName(of:)) ?? bundleIdentifier
        lastNames?.names[bundleIdentifier] = name
        return name
    }
}
