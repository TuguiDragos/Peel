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
    /// What Peel selects for the person, worked out again whenever the helper changes.
    private(set) var suggested: Set<URL> = []
    var selectable: Set<URL> { choices.selectable }
    private var measuredSizes: [URL: Int64] = [:]
    /// The bundle identifiers of the chosen apps that stay (`BulkUninstallation.staying(selected:)`), worked out
    /// again whenever the selection changes.
    private(set) var staying: Set<String> = []

    init(apps: [InstalledApp]) {
        self.apps = apps
    }

    var items: [BulkUninstallation.Item] { bulk?.items ?? [] }

    /// What a confirmation would ask about now: the selection, with the sizes this scan measured.
    var request: RemovalRequest {
        RemovalRequest(urls: selectedURLs, sizes: [URL: Int64](measured: selectedURLs.map { ($0, measuredSizes[$0]) }))
    }

    var total: SizeTotal { bulk?.total ?? SizeTotal(known: 0, isComplete: true) }

    var privilegedURLs: Set<URL> { bulk?.privilegedURLs ?? [] }

    var requiresHelper: Bool { bulk?.privilegedURLs.isEmpty == false }

    var unreadableLocations: [SearchLocation] { bulk?.unreadableLocations ?? [] }

    /// The processes of the chosen apps with anything of theirs selected that run now, helpers included. Files never
    /// move out from under a running app, so an app that stays still quits before a file of its own moves.
    var runningProcesses: [NSRunningApplication] {
        let running = RunningCopies.current
        let owners = Set(items.filter { selectedURLs.contains($0.url) }.flatMap(\.apps))
        return apps.filter { owners.contains($0.bundleIdentifier) }.flatMap { app in
            RunningCopies.belonging(to: app, among: running, installedApps: installedApps)
                .compactMap { NSRunningApplication(processIdentifier: $0.identifier) }
        }
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
        guard let (result, revision) = await scanRun.run({
            let revision = ExclusionsStore.shared.revision
            return (await BulkUninstallation.prepare(
                apps,
                installedApps: installedApps,
                exclusions: ExclusionsStore.shared.exclusions,
                casks: casks,
                receipts: receipts
            ), revision)
        }) else { return }
        bulk = result
        exclusionsRevision = revision
        applications = result.items.filter(\.isApplication)
        recommendedFiles = result.items.filter { !$0.isApplication && $0.isRecommended }
        filesToReview = result.items.filter { !$0.isApplication && !$0.isRecommended }
        appsInTheTrash = Set(result.uninstallations.filter(\.isAppInTheTrash).map(\.app.url))
        measuredSizes = [URL: Int64](measured: result.items.map { ($0.url, $0.isMeasured ? $0.size : nil) })
        self.installedApps = installedApps
        suggested = result.suggestedSelection(canUseHelper: self.canUseHelper)
        selectedURLs = choices.update(selectedURLs, in: result, canUseHelper: self.canUseHelper)
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

    /// Moves what `request` asked about, whatever has been selected since.
    func move(_ request: RemovalRequest) async -> TrashResult {
        guard let bulk else { return TrashResult() }
        return await bulk.move(request.urls, using: TrashService(exclusions: ExclusionsStore.shared.exclusions))
    }

    /// The source History records: up to three app names, or a count in English that History shows in the
    /// user's language through `historySourceKey`.
    var historySource: String {
        guard apps.count > 3 else { return apps.map(\.name).joined(separator: ", ") }
        return String(AttributedString(localized: "^[\(apps.count) app](inflect: true)", locale: Locale(identifier: "en")).characters)
    }

    var historySourceKey: String? {
        apps.count > 3 ? "apps.\(apps.count)" : nil
    }
}
