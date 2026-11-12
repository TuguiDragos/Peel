import AppKit
import Foundation
import Observation
import PeelCore

/// Several apps reviewed and removed in one go.
@Observable
final class BulkRemovalPlan {
    let apps: [InstalledApp]
    private(set) var bulk: BulkUninstallation?
    /// The scan this page runs, which a newer one or the Stop button ends.
    let scanRun = ScanRun()
    var isScanning: Bool { scanRun.isRunning }
    /// The question before a removal, and the removal it starts.
    let question = RemovalQuestion()
    var isRemoving: Bool { question.isRemoving }
    /// The options of the removal, kept here rather than in the page, so a click updates only the option's own row.
    var resetsPrivacy = false
    var removesDockTiles = true
    /// Every installed app as of the last scan, to tell a chosen app's processes from another installed app's.
    private var installedApps: [InstalledApp] = []
    var selectedURLs: Set<URL> = [] {
        didSet { staying = bulk?.staying(selected: selectedURLs) ?? [] }
    }
    private var choices = UninstallSelection()
    /// Whether the helper can act, as last heard, so a scan that lands after it changed selects by what is true now.
    private var canUseHelper = false
    /// Worked out once per scan, because the page reads each of these on every change, and its list builds every
    /// row again for each one.
    private(set) var applications: [BulkUninstallation.Item] = []
    /// The files Peel would select if their apps go, as an app's own page lists them under Recommended.
    private(set) var recommendedFiles: [BulkUninstallation.Item] = []
    /// The files nothing selects for the person, as an app's own page lists them under Review Before Removing.
    private(set) var filesToReview: [BulkUninstallation.Item] = []
    /// The chosen apps already in the Trash, which neither go nor stay: only what they left behind can move.
    private(set) var appsInTheTrash: Set<URL> = []
    /// The chosen apps the Dock holds a tile for, read once per scan, so Rescan shows it as it is now.
    private(set) var appsInTheDock: Set<URL> = []
    /// What Peel selects for the person, worked out again whenever the helper changes.
    private(set) var suggested: Set<URL> = []
    var selectable: Set<URL> { choices.selectable }
    private var measuredSizes: [URL: Int64] = [:]
    /// The bundle identifiers of the chosen apps that stay (`BulkUninstallation.staying(selected:)`), worked out
    /// again whenever the selection changes.
    private(set) var staying: Set<String> = []

    private let systemExtensions: AppExtensions.SystemExtensionsAnswer

    init(
        apps: [InstalledApp],
        systemExtensions: @escaping AppExtensions.SystemExtensionsAnswer = AppExtensions.askingMacOS
    ) {
        self.apps = apps
        self.systemExtensions = systemExtensions
    }

    /// The other copies of `app` that stay installed, which share its privacy permissions.
    func otherCopies(of app: InstalledApp) -> [URL] {
        bulk?.uninstallations.first { $0.app.url == app.url }?.otherCopies ?? []
    }

    var items: [BulkUninstallation.Item] { bulk?.items ?? [] }

    /// The chosen apps already in the Trash that hold a tile in the Dock and a file of their own that can be selected.
    var appsInTheTrashWithTiles: [InstalledApp] {
        appsInTheTrash(withFilesAmong: selectable).filter { appsInTheDock.contains($0.url) }
    }

    func appsInTheTrash(withFilesAmong urls: Set<URL>) -> [InstalledApp] {
        guard let bulk, !appsInTheTrash.isEmpty else { return [] }
        return apps.filter { appsInTheTrash.contains($0.url) && !bulk.files(of: $0.reference).isDisjoint(with: urls) }
    }

    /// What a confirmation would ask about now: the selection, with the sizes this scan measured.
    var request: RemovalRequest {
        RemovalRequest(
            urls: selectedURLs,
            sizes: [URL: Int64](measured: selectedURLs.map { ($0, measuredSizes[$0]) }),
            sharingStorage: Set(items.filter(\.sharesStorage).map(\.url))
        )
    }

    var total: SizeTotal { bulk?.total ?? SizeTotal(known: 0, isComplete: true) }

    var privilegedURLs: Set<URL> { bulk?.privilegedURLs ?? [] }

    var rowsWaitingForTheHelper: Int { bulk?.rowsWaitingForTheHelper ?? 0 }

    var unreadableLocations: [SearchLocation] { bulk?.unreadableLocations ?? [] }

    /// What the alert asks: an app's own words when one runs, as its page says them, whether it goes or only its files
    /// do, and for several, the plural when all of them go.
    static func quitTitle(running: [InstalledApp], going: Set<URL>) -> LocalizedStringResource {
        if running.count == 1, let app = running.first {
            return going.contains(app.url) ? "Quit \(app.name) before removing it." : "Quit \(app.name) before removing its files."
        }
        return running.allSatisfy { going.contains($0.url) } ? "Quit these apps before removing them." : "Quit these apps first."
    }

    /// The chosen apps with anything of theirs selected that have a process to quit, and those processes, helpers
    /// included, each once: two copies of an app share their helpers. Files never move out from under a running app,
    /// so an app that stays still quits before a file of its own moves. What quits is what `RunningCopies.toQuit` says,
    /// with the jobs of all these apps left running, since the move stops them.
    func toQuit() async -> (apps: [InstalledApp], processes: [NSRunningApplication]) {
        let running = RunningCopies.current
        let owners = owningSelected.filter { app in
            !RunningCopies.belonging(to: app, among: running, installedApps: installedApps).isEmpty
        }
        guard !owners.isEmpty else { return ([], []) }
        let jobs = await RunningCopies.keptRunningByJobs(inside: owners.map(\.url))
        var seen: Set<pid_t> = []
        var apps: [InstalledApp] = []
        var processes: [NSRunningApplication] = []
        for app in owners {
            let own = await RunningCopies.toQuit(
                beforeMoving: app, among: running, installedApps: installedApps, keptByJobs: { _ in jobs }
            )
            if !own.isEmpty { apps.append(app) }
            processes += own.filter { seen.insert($0.identifier).inserted }
                .compactMap { NSRunningApplication(processIdentifier: $0.identifier) }
        }
        return (apps, processes)
    }

    private var owningSelected: [InstalledApp] {
        let owners = Set(items.filter { selectedURLs.contains($0.url) }.flatMap(\.apps))
        return apps.filter { owners.contains($0.reference) }
    }

    /// The revision of the exclusions the last scan read, nil before the first.
    private(set) var exclusionsRevision: Int?

    func refresh(
        installedApps: [InstalledApp],
        canUseHelper: Bool,
        casks: [HomebrewPackage] = [],
        receipts: Set<String> = []
    ) async {
        self.canUseHelper = canUseHelper
        let apps = apps
        let systemExtensions = systemExtensions
        guard let (result, revision, inTheDock) = await scanRun.run({
            let revision = ExclusionsStore.shared.revision
            async let inTheDock = DockTiles().holding(apps.map(\.url))
            return (await BulkUninstallation.prepare(
                apps,
                installedApps: installedApps,
                exclusions: ExclusionsStore.shared.exclusions,
                casks: casks,
                receipts: receipts,
                systemExtensions: systemExtensions
            ), revision, await inTheDock)
        }) else { return }
        exclusionsRevision = revision
        self.installedApps = installedApps
        appsInTheDock = inTheDock
        show(result)
    }

    private func show(_ result: BulkUninstallation) {
        bulk = result
        applications = result.items.filter(\.isApplication)
        recommendedFiles = result.items.filter { !$0.isApplication && $0.isRecommended }
        filesToReview = result.items.filter { !$0.isApplication && !$0.isRecommended }
        appsInTheTrash = Set(result.uninstallations.filter(\.isAppInTheTrash).map(\.app.url))
        measuredSizes = [URL: Int64](measured: result.items.map { ($0.url, $0.isMeasured ? $0.size : nil) })
        suggested = result.suggestedSelection(canUseHelper: canUseHelper)
        selectedURLs = choices.update(selectedURLs, in: result, canUseHelper: canUseHelper)
    }

    /// Asks macOS again about the chosen apps' system extensions, which the person turns on and off in System
    /// Settings, and brings the page in line with the answer without scanning their files again.
    func followSystemExtensions() async {
        guard let apps = bulk?.uninstallations.map(\.app) else { return }
        let installed = await systemExtensions()
        var carried: [URL: CarriedSystemExtensions] = [:]
        for app in apps {
            carried[app.url] = await AppExtensions.installed(carriedBy: app) { installed }
        }
        guard let current = bulk else { return }
        var updated = current.uninstallations
        for index in updated.indices {
            if let answer = carried[updated[index].app.url] { updated[index].installedSystemExtensions = answer }
        }
        guard updated.map(\.installedSystemExtensions) != current.uninstallations.map(\.installedSystemExtensions),
              question.mayScan() else { return }
        show(BulkUninstallation(uninstallations: updated))
    }

    /// Brings the selection in line with the helper as it is now, without scanning again.
    func follow(canUseHelper: Bool) {
        self.canUseHelper = canUseHelper
        guard let bulk else { return }
        suggested = bulk.suggestedSelection(canUseHelper: canUseHelper)
        selectedURLs = choices.update(selectedURLs, in: bulk, canUseHelper: canUseHelper)
    }

    /// Deselecting an app's bundle keeps the app, so its files leave the selection with it
    /// (`UninstallSelection.personChanged(from:to:in:)`).
    func select(_ selection: Set<URL>) {
        selectedURLs = bulk.map { choices.personChanged(from: selectedURLs, to: selection, in: $0) } ?? selection
    }

    /// Moves what `request` asked about with `service`, whatever has been selected since.
    func move(_ request: RemovalRequest, using service: TrashService) async -> TrashResult {
        guard let bulk else { return TrashResult() }
        return await bulk.move(request.urls, using: service)
    }

    /// Records `result` in History, what moved named by the apps it belonged to and what stayed by its own apps.
    func record(
        _ result: TrashResult,
        sizes: [URL: Int64],
        sharingStorage: Set<URL>,
        in history: RemovalHistoryStore
    ) async {
        var removal = RemovalInProgress()
        let moved = bulk?.apps(owning: result.trashed.map(\.originalURL)) ?? []
        let stayed = bulk?.apps(owning: result.failures.map(\.url)) ?? []
        var trashed = result
        trashed.failures = []
        let parts = [
            (trashed, part(naming: moved)),
            (TrashResult(failures: result.failures), part(naming: stayed)),
        ]
        for (result, part) in parts {
            await history.record(result, part: part, sizes: sizes, sharingStorage: sharingStorage, in: &removal)
        }
        history.finish(removal)
    }

    /// Up to three app names, or a count in English that History shows in the user's language through the key.
    func part(naming named: [InstalledApp]) -> RemovalPart {
        let named = named.isEmpty ? apps : named
        let tool = Tool.applications.rawValue
        guard named.count > 3 else {
            return RemovalPart(source: named.map(\.name).joined(separator: ", "), sourceKey: nil, tool: tool)
        }
        // Written in English, not looked up: the catalog would give the language Peel runs in, and past three the
        // English is always plural.
        return RemovalPart(source: "\(named.count) apps", sourceKey: "apps.\(named.count)", tool: tool)
    }
}
