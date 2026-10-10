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

extension AppSource {
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
    /// The folders the person chose for apps, beside the Applications folders, or nil when their list cannot be read.
    /// `PeelApp` watches them and reads the apps again when they change.
    private(set) var folders = AppFolders().load()
    private(set) var couldNotSaveFolders = false
    /// What the last reading of the folders could not read, so the apps in it are missing from `apps`
    /// (`AppScan.unreadable`).
    private(set) var unreadable: [URL] = []
    /// Whether Full Disk Access would open what the last reading could not read.
    private(set) var unreadableNeedsFullDiskAccess = false
    private(set) var updateStatuses: [InstalledApp.ID: UpdateStatus] = [:] {
        didSet { updatesRevision += 1 }
    }

    /// Incremented by anything that changes which apps have an update waiting, so the list redraws.
    private(set) var updatesRevision = 0
    private var updateRounds = UpdateRounds<InstalledApp.ID>() {
        didSet {
            if updateRounds.checking.isEmpty {
                heldUpdates = nil
            } else if oldValue.checking.isEmpty {
                heldUpdates = Set(appsWithUpdates.map(\.id))
            }
        }
    }
    var appsCheckingForUpdates: Set<InstalledApp.ID> { updateRounds.checking }
    /// The apps with an update when the current round of checks began. The menu bar shows them until the round
    /// ends, rather than a count that climbs as answers arrive seconds apart.
    private var heldUpdates: Set<InstalledApp.ID>?
    private(set) var sizes: [InstalledApp.ID: Int64] = [:] {
        didSet { sizesRevision += 1 }
    }
    /// The apps whose bundle could not be measured, by time or by macOS, so their size is not known rather than
    /// still to come. The list reads "Unknown" for them and sorts them first.
    private(set) var unmeasured: Set<InstalledApp.ID> = [] {
        didSet { sizesRevision += 1 }
    }

    /// The apps whose bundle shares most of its storage with another copy (`FolderContents.sharesMostOfItsStorage`),
    /// so its size is far below the space it takes.
    private(set) var sharingStorage: Set<InstalledApp.ID> = []

    /// Incremented when a size arrives. Only the size sort depends on it, so other sorts keep their cached list.
    private(set) var sizesRevision = 0
    private(set) var lastUpdateChecks: [InstalledApp.ID: Date] = [:]
    /// How the last upgrade run from each app's page went. Kept here rather than on the page: a successful upgrade
    /// is another build, so the page is built again, and the new one shows the result.
    private var upgrades: [InstalledApp.ID: Upgrade] = [:]
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
    private(set) var ignoredApps = Set(
        UserDefaults.standard.stringArray(forKey: SettingsKey.ignoredUpdateApps) ?? []
    ) {
        didSet { updatesRevision += 1 }
    }

    private(set) var skippedVersions = UserDefaults.standard.dictionary(forKey: SettingsKey.skippedUpdateVersions)
        as? [String: String] ?? [:] {
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
    /// What is new in each waiting update, read at launch, so a page shows it with no connection too.
    private(set) var releaseNotes = ReleaseNotesMemory()
    private let releaseNotesStore = ReleaseNotesStore()
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

    /// The apps listed, and what could not be read of them, which Orphaned Files checks its files against.
    struct Listing: Equatable {
        let revision: Int
        let unreadable: [URL]
    }

    var listing: Listing {
        Listing(revision: revision, unreadable: unreadable)
    }

    /// The first reading of the folders, at launch. A reading the folder watch starts meanwhile takes its place
    /// and lists the apps itself.
    func load() async {
        isLoading = true
        lastRead = .now
        if !hasLoaded {
            releaseNotes = await releaseNotesStore.load()
        }
        let found = await scanRun.run { await AppCatalog.scan() }
        if let found {
            keepUnreadable(of: found)
            adopt(found.apps)
        }
        recall()
        isLoading = false
        hasLoaded = true
        if let found {
            await AppMemory().remember(found.apps)
        }
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

    /// Sets the list of folders aside when it cannot be read, so the folders can be chosen again.
    func startFoldersOver() {
        changeFolders { $0.startOver() }
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
        guard let scan = await scanRun.run({ await AppCatalog.scan() }) else { return [] }
        lastRead = .now
        keepUnreadable(of: scan)
        let found = scan.apps
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

    /// Checks again what a reading found at another build: whether it has an update and who signs it, since what
    /// Peel learned was about the old build.
    func checkAgain(_ changed: [InstalledApp]) async {
        guard !changed.isEmpty else { return }
        await checkForUpdates(changed, force: true)
        await checkSigningTeams()
    }

    private func keepUnreadable(of scan: AppScan) {
        if unreadable != scan.unreadable { unreadable = scan.unreadable }
        if unreadableNeedsFullDiskAccess != scan.needsFullDiskAccess {
            unreadableNeedsFullDiskAccess = scan.needsFullDiskAccess
        }
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
        let changed = listed.filter { app in previous[app.id].map { !$0.isTheSameBuild(as: app) } ?? false }
        let present = Set(listed.map(\.id))
        IconCache.forget(previous.keys.filter { !present.contains($0) } + changed.map(\.url))
        apps = listed
        revision += 1
        matchHomebrewApps()

        let stale = Set(changed.map(\.id))
        let keeps = { (id: InstalledApp.ID) in present.contains(id) && !stale.contains(id) }
        sizes = sizes.filter { keeps($0.key) }
        unmeasured = unmeasured.filter(keeps)
        sharingStorage = sharingStorage.filter(keeps)
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
        return revealed.filter {
            !listed.contains($0.id) && FileManager.default.fileExists(atPath: $0.url.path(percentEncoded: false))
        }
    }

    /// Restores the update answers saved by earlier runs, for apps still at the build they describe.
    private func recall() {
        for app in apps {
            guard let identifier = app.bundleIdentifier, let remembered = memory[identifier], remembered.describes(app)
            else { continue }
            updateStatuses[app.id] = remembered.status
            if let checked = remembered.checked {
                lastUpdateChecks[app.id] = checked
            }
        }
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
        let asked = Dictionary(missing.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        await withTaskGroup(of: (InstalledApp.ID, FolderContents?).self) { group in
            var pending = missing.makeIterator()
            for _ in 0..<Self.concurrentSizeReads {
                guard let app = pending.next() else { break }
                _ = group.addTaskUnlessCancelled { (app.id, await FileSize.contents(of: app.url)) }
            }
            while let (id, contents) = await group.next() {
                let measured = contents.flatMap { $0.couldNotBeRead ? nil : $0 }
                // A walk given up because the list changed says nothing about the bundle, and a bundle replaced
                // while it was walked is another build, so neither answer is kept.
                if !Task.isCancelled, let app = asked[id],
                   apps.contains(where: { $0.id == id && $0.isTheSameBuild(as: app) }) {
                    if let measured {
                        sizes[id] = measured.size
                        unmeasured.remove(id)
                        if measured.sharesMostOfItsStorage {
                            sharingStorage.insert(id)
                        } else {
                            sharingStorage.remove(id)
                        }
                    } else {
                        unmeasured.insert(id)
                    }
                }
                if !Task.isCancelled, let app = pending.next() {
                    _ = group.addTaskUnlessCancelled { (app.id, await FileSize.contents(of: app.url)) }
                }
            }
        }
    }

    func source(of app: InstalledApp) -> AppSource {
        AppSource.of(app, installedByHomebrew: homebrewApps[app.id] != nil)
    }

    func developer(of app: InstalledApp) -> String? {
        appDevelopers.developer(of: app, remembered: app.bundleIdentifier.flatMap { memory[$0]?.developer })
    }

    var developers: [String] {
        AppDevelopers.offered(apps.compactMap(developer(of:)), chosen: selectedDeveloper)
    }

    private var appDevelopers: AppDevelopers {
        if let lastTeams, lastTeams.revision == revision { return lastTeams.developers }
        let developers = AppDevelopers(apps)
        lastTeams = (revision, developers)
        return developers
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
    @ObservationIgnored private var lastTeams: (revision: Int, developers: AppDevelopers)?

    /// The apps the user excluded. Worked out again only when the apps or the exclusions change, since each
    /// check resolves the app's path on disk.
    func excludedIDs(by exclusions: Exclusions) -> Set<InstalledApp.ID> {
        if let lastExcluded, lastExcluded.revision == revision, lastExcluded.exclusions == exclusions {
            return lastExcluded.ids
        }
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
        let filter = AppListFilter(
            text: searchText, sources: sources, developer: selectedDeveloper, onlyUnused: showsOnlyUnused
        )
        let result = apps.filter {
            filter.keeps($0, source: source(of: $0), developer: developer(of: $0), isUnused: isUnused($0))
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
        guard UserDefaults.standard.isOn(SettingsKey.checksForAppUpdates, whenNeverSet: true) else { return }
        let now = Date.now
        // An app is checked on a schedule kept by its identifier, so an app with none is left to Homebrew's answer.
        // Peel's own copies are left to Sparkle, which checks the one running and is the only way it updates.
        let wanted = targets.filter { app in
            guard let identifier = app.bundleIdentifier, !app.isPeelItself, !isIgnored(app),
                  !appsInATrash.contains(app.id)
            else { return false }
            guard !force else { return true }
            // Already being checked by another round: a second answer could double the wait for the next check.
            guard !appsCheckingForUpdates.contains(app.id) else { return false }
            // An update whose notes were never asked for is checked once now rather than on its next turn.
            let notesWait = releaseNotes.asks(about: updateStatuses[app.id], of: app, with: updatePreferences)
            return memory[identifier]?.schedule.isDue(at: now) ?? true || notesWait
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
        let notesBefore = releaseNotes
        var notesToAsk: [ReleaseNotesQuestion] = []

        await withTaskGroup(of: (InstalledApp.ID, UpdateAnswer).self) { group in
            var pending = wanted.makeIterator()
            for _ in 0..<Self.concurrentUpdateChecks {
                guard let app = pending.next() else { break }
                _ = group.addTaskUnlessCancelled {
                    (app.id, await checker.answer(for: app, preference: preference, casks: casks))
                }
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
                guard let app = asked[id], apps.contains(where: { $0.id == id && $0.isTheSameBuild(as: app) }) else {
                    continue
                }
                let kept = status.following(updateStatuses[id])
                // Any write redraws the whole Applications list, so an answer that changes nothing is not written.
                if updateStatuses[id] != kept {
                    updateStatuses[id] = kept
                }
                if status != .failed {
                    lastUpdateChecks[id] = .now
                }
                guard let identifier = app.bundleIdentifier else { continue }
                memory[identifier] = UpdateMemory(
                    status: kept,
                    schedule: UpdateSchedule.next(after: status, following: memory[identifier]?.schedule),
                    checked: status == .failed ? memory[identifier]?.checked : .now,
                    describing: app,
                    developer: answer.developer ?? memory[identifier]?.developer
                )
                // Only an answer that found this update can say what is new in it; a failed one keeps what was known.
                if case .updateAvailable(let version, _, _) = kept, answer.status == kept {
                    if let notes = answer.notes {
                        releaseNotes.record(.found(notes), of: identifier, version: version)
                    } else if releaseNotes.asks(about: kept, of: app, with: updatePreferences) {
                        notesToAsk.append(ReleaseNotesQuestion(app: app, answer: answer, version: version))
                    }
                }
                if let app = pending.next() {
                    _ = group.addTaskUnlessCancelled {
                        (app.id, await checker.answer(for: app, preference: preference, casks: casks))
                    }
                }
            }
        }
        guard !Task.isCancelled, updateRounds.isCurrent(round) else { return }
        UpdateMemoryStore.save(memory)
        await ask(notesToAsk, checker: checker)
        var waiting: [String: String] = [:]
        for app in apps {
            if let version = updateStatuses[app.id]?.version, let identifier = app.bundleIdentifier {
                waiting[identifier] = version
            }
        }
        releaseNotes.keep(only: waiting)
        if releaseNotes != notesBefore {
            await releaseNotesStore.save(releaseNotes)
        }
    }

    /// What is new in the update `app` is waiting for, when it is known.
    func releaseNotes(of app: InstalledApp) -> ReleaseNotes? {
        guard let identifier = app.bundleIdentifier else { return nil }
        return updateStatuses[app.id]?.version.flatMap { releaseNotes.notes(of: identifier, version: $0) }
    }

    /// An update whose answer did not say what is new in it.
    private struct ReleaseNotesQuestion: Sendable {
        let app: InstalledApp
        let answer: UpdateAnswer
        let version: String
    }

    /// Asks the app's own addresses for the notes the round's answers did not carry, a few at a time.
    private func ask(_ questions: [ReleaseNotesQuestion], checker: UpdateChecker) async {
        await withTaskGroup(of: (ReleaseNotesQuestion, ReleaseNotesLookup).self) { group in
            var pending = questions.makeIterator()
            func askNext() {
                guard let question = pending.next() else { return }
                group.addTask { (question, await checker.releaseNotes(for: question.app, answer: question.answer)) }
            }
            for _ in 0..<Self.concurrentUpdateChecks {
                askNext()
            }
            while let (question, lookup) = await group.next() {
                if let identifier = question.app.bundleIdentifier {
                    releaseNotes.record(lookup, of: identifier, version: question.version)
                }
                askNext()
            }
        }
    }

    /// The user's update settings as one value. The command line reads the same settings from the same keys,
    /// so the app and `peel` can't disagree about what is waiting.
    var updatePreferences: UpdatePreferences {
        UpdatePreferences(
            source: updateSource,
            ignoredApps: ignoredApps,
            skippedVersions: skippedVersions
        )
    }

    /// Whether an update is waiting for `app`. An ignored app has none, and neither has one whose waiting
    /// version was skipped. The list, the menu bar, and the notification all ask this, so they always agree.
    /// Peel's own updates are Sparkle's (`PeelUpdater`).
    func hasUpdate(_ app: InstalledApp) -> Bool {
        !app.isPeelItself && updatePreferences.isWaiting(updateStatuses[app.id], for: app)
    }

    /// The answer about `app`'s updates that its page shows: an update the user muted is not announced again.
    func shownUpdateStatus(of app: InstalledApp) -> UpdateStatus? {
        app.isPeelItself ? nil : updatePreferences.shownStatus(updateStatuses[app.id], for: app)
    }

    var appsWithUpdates: [InstalledApp] { apps.filter(hasUpdate) }

    /// The apps the menu bar item and its panel count. They follow `hasUpdate(_:)`, but while a round of checks runs
    /// they are the ones from when the round began.
    var menuBarUpdates: [InstalledApp] {
        guard let heldUpdates else { return appsWithUpdates }
        return apps.filter { heldUpdates.contains($0.id) }
    }

    var menuBarUpdateCount: Int { menuBarUpdates.count }

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
        var references = ignoredApps
        if isIgnored {
            references.insert(app.reference)
        } else {
            references.remove(app.reference)
        }
        ignoredApps = references
        UserDefaults.standard.set(Array(references).sorted(), forKey: SettingsKey.ignoredUpdateApps)
    }

    func skippedVersion(for app: InstalledApp) -> String? {
        skippedVersions[app.reference]
    }

    func skip(version: String, for app: InstalledApp) {
        skippedVersions[app.reference] = version
        UserDefaults.standard.set(skippedVersions, forKey: SettingsKey.skippedUpdateVersions)
    }

    /// Undoes both a skipped version and "never check this app", by `InstalledApp.reference`: what was muted may not
    /// be installed anymore, and then there is no `InstalledApp` to name it with.
    func unmute(_ reference: String) {
        ignoredApps.remove(reference)
        skippedVersions.removeValue(forKey: reference)
        UserDefaults.standard.set(ignoredApps.sorted(), forKey: SettingsKey.ignoredUpdateApps)
        UserDefaults.standard.set(skippedVersions, forKey: SettingsKey.skippedUpdateVersions)
    }

    /// Called often, including every time the Applications list appears. Apps are matched to casks again only
    /// when the casks changed, since `adopt` already does it when the apps change, and matching holds the
    /// main thread.
    /// `knowsItsOwnApps` is true when `packages` says of every app whether Homebrew installed it, and not while
    /// Homebrew could not be read.
    struct Upgrade {
        /// The app as the upgrade left it.
        let app: InstalledApp
        let succeeded: Bool
    }

    /// How the last upgrade of `app` went, while `app` is still the build it left.
    func upgrade(of app: InstalledApp) -> Upgrade? {
        upgrades[app.id].flatMap { $0.app.isTheSameBuild(as: app) ? $0 : nil }
    }

    func record(_ upgrade: Upgrade?, of app: InstalledApp) {
        upgrades[app.id] = upgrade
    }

    func loadHomebrewCasks(_ packages: [HomebrewPackage], knowsItsOwnApps: Bool) {
        let casks = packages.filter { $0.kind == .cask }
        if casks != self.casks {
            self.casks = casks
            matchHomebrewApps()
        }
        if knowsItsOwnApps {
            forgetUpdatesHomebrewNoLongerOffers()
        }
        applyHomebrewStatuses()
    }

    /// Forgets an update Homebrew reported for an app it no longer counts as its own, saved answer included, so the
    /// app is due and its own feed answers at the next round.
    private func forgetUpdatesHomebrewNoLongerOffers() {
        let outlived = Set(updateStatuses.filter { !$0.value.holds(whileHomebrews: homebrewApps[$0.key] != nil) }.keys)
        guard !outlived.isEmpty else { return }
        updateStatuses = updateStatuses.filter { !outlived.contains($0.key) }
        lastUpdateChecks = lastUpdateChecks.filter { !outlived.contains($0.key) }
        for app in apps where outlived.contains(app.id) {
            if let identifier = app.bundleIdentifier { memory[identifier] = nil }
        }
        UpdateMemoryStore.save(memory)
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
        teamChanges = Dictionary(
            outcome.changes.map { ($0.bundleIdentifier, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        teamRecordProblem = outcome.problem
    }

    func acknowledgeTeamChange(for app: InstalledApp) async {
        guard let identifier = app.bundleIdentifier else { return }
        teamChanges.removeValue(forKey: identifier)
        if let problem = await teamRegistry.acknowledge(identifier) {
            teamRecordProblem = problem
        }
    }

    /// Keeps a record of signers that cannot be read beside a new one, and records who signs each app now.
    func startTeamRecordOver() async {
        guard await teamRegistry.startOver() else { return }
        await checkSigningTeams()
    }

    /// Selects the apps together, adding each first when it lives outside the scanned folders, for example in
    /// the Trash. What is not an app is passed over, and false means none was.
    @discardableResult
    func reveal(_ urls: [URL]) async -> Bool {
        var chosen: Set<InstalledApp.ID> = []
        for url in urls {
            if let id = await listed(url) {
                chosen.insert(id)
            }
        }
        guard !chosen.isEmpty else { return false }
        selection = chosen
        return true
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

    /// The name of the app `reference` names (`InstalledApp.reference`): the listed app's, or the one Finder shows
    /// for an app macOS knows elsewhere by that identifier, such as a helper or a Nightly build on another disk. The
    /// reference itself when macOS knows none.
    func name(forReference reference: String) -> String {
        if lastNames?.revision != revision {
            lastNames = (
                revision,
                Dictionary(apps.map { ($0.reference, $0.name) }, uniquingKeysWith: { first, _ in first })
            )
        }
        if let name = lastNames?.names[reference] { return name }
        let name = AppInspector.knownName(forBundleIdentifier: reference)
        lastNames?.names[reference] = name
        return name
    }
}
