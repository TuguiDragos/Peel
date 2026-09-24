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
    private(set) var isRemoving = false
    /// Every installed app as of the last scan, to tell a chosen app's processes from another installed app's.
    private var installedApps: [InstalledApp] = []
    var selectedURLs: Set<URL> = []

    init(apps: [InstalledApp]) {
        self.apps = apps
    }

    var items: [BulkUninstallation.Item] { bulk?.items ?? [] }

    /// False when a selected item's size is unknown, so the bar reads "Over" the sum.
    var isSelectionMeasured: Bool {
        items.allSatisfy { !selectedURLs.contains($0.url) || $0.isMeasured }
    }

    var selectedSize: Int64 {
        items.filter { selectedURLs.contains($0.url) }.reduce(0) { $0 + $1.size }
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
        selectedURLs = result.suggestedSelection(canUseHelper: canUseHelper)
    }

    func removeSelected() async -> TrashResult {
        guard let bulk else { return TrashResult() }
        isRemoving = true
        defer { isRemoving = false }
        let urls = bulk.removalOrder(of: selectedURLs)
        return await TrashService(exclusions: ExclusionsStore.shared.exclusions)
            .trash(urls, usingHelperFor: bulk.privilegedURLs)
    }

    var sizes: [URL: Int64] {
        Dictionary(items.map { ($0.url, $0.size) }, uniquingKeysWith: { first, _ in first })
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
