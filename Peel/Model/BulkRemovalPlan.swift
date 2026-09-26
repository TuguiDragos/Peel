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
    var selectedURLs: Set<URL> = []
    private var choices = UninstallSelection()
    /// Whether the helper can act, as last heard, so a scan that lands after it changed selects by what is true now.
    private var canUseHelper = false

    init(apps: [InstalledApp]) {
        self.apps = apps
    }

    var items: [BulkUninstallation.Item] { bulk?.items ?? [] }

    /// What a confirmation would ask about now: the selection, with the sizes this scan measured.
    var request: RemovalRequest {
        RemovalRequest(
            urls: selectedURLs,
            sizes: [URL: Int64](measured: items.filter { selectedURLs.contains($0.url) }.map { ($0.url, $0.isMeasured ? $0.size : nil) })
        )
    }

    var total: SizeTotal { bulk?.total ?? SizeTotal(known: 0, isComplete: true) }

    var privilegedURLs: Set<URL> { bulk?.privilegedURLs ?? [] }

    var requiresHelper: Bool { bulk?.privilegedURLs.isEmpty == false }

    var unreadableLocations: [SearchLocation] { bulk?.unreadableLocations ?? [] }

    /// The chosen apps that are running, helpers included, and whose bundle is selected. An app whose bundle
    /// the user deselected stays, so it is neither named nor quit.
    var runningApps: [InstalledApp] {
        let running = RunningCopies.current
        return apps.filter { selectedURLs.contains($0.url) && !RunningCopies.belonging(to: $0, among: running, installedApps: installedApps).isEmpty }
    }

    func quitRunningApps() {
        let running = RunningCopies.current
        for app in runningApps {
            for process in RunningCopies.belonging(to: app, among: running, installedApps: installedApps) {
                NSRunningApplication(processIdentifier: process.identifier)?.terminate()
            }
        }
    }

    func refresh(installedApps: [InstalledApp], canUseHelper: Bool, casks: [HomebrewPackage] = [], receipts: Set<String> = []) async {
        self.canUseHelper = canUseHelper
        let apps = apps
        guard let result = await scanRun.run({
            await BulkUninstallation.prepare(
                apps,
                installedApps: installedApps,
                exclusions: ExclusionsStore.shared.exclusions,
                casks: casks,
                receipts: receipts
            )
        }) else { return }
        bulk = result
        self.installedApps = installedApps
        selectedURLs = choices.update(selectedURLs, in: result, canUseHelper: self.canUseHelper)
    }

    /// Brings the selection in line with the helper as it is now, without scanning again.
    func follow(canUseHelper: Bool) {
        self.canUseHelper = canUseHelper
        guard let bulk else { return }
        selectedURLs = choices.update(selectedURLs, in: bulk, canUseHelper: canUseHelper)
    }

    /// Moves what `request` asked about, whatever has been selected since.
    func move(_ request: RemovalRequest) async -> TrashResult {
        guard let bulk else { return TrashResult() }
        let urls = bulk.removalOrder(of: request.urls)
        return await TrashService(exclusions: ExclusionsStore.shared.exclusions)
            .trash(urls, usingHelperFor: bulk.privilegedURLs)
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
