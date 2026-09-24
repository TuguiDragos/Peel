import AppKit
import Foundation
import Observation
import PeelCore

@Observable
final class RemovalPlan {
    let app: InstalledApp
    private(set) var uninstallation: Uninstallation?
    /// The scan this page runs, which a newer one or the Stop button ends.
    let scanRun = ScanRun()
    var isScanning: Bool { scanRun.isRunning }
    private(set) var isRemoving = false
    /// The kinds of files and links this app opens by default, so the page can say which app opens them once
    /// it is gone.
    private(set) var defaultRoles: [DefaultRole] = []
    /// Every installed app as of the last scan. It tells this app's running helpers apart from another app's.
    private var installedApps: [InstalledApp] = []
    /// Read from the bundle once per scan, off the main actor. The page reads both on every checkbox change,
    /// and finding the uninstaller lists whole folders, such as Applications.
    private(set) var vendorUninstaller: URL?
    private(set) var systemExtensions: [String] = []
    var selectedURLs: Set<URL> = []
    /// Worked out once per scan, because the page reads each of these several times on every change.
    private(set) var recommended: [Leftover] = []
    private(set) var needsReview: [Leftover] = []
    private(set) var recommendedMovable: (count: Int, size: SizeTotal) = (0, SizeTotal([]))
    private(set) var reviewMovable: (count: Int, size: SizeTotal) = (0, SizeTotal([]))
    /// The size of everything that could be moved, the app included, which the header shows.
    private(set) var total = SizeTotal([])
    private var leftoverSizes: [URL: (size: Int64, isMeasured: Bool)] = [:]

    init(app: InstalledApp) {
        self.app = app
    }

    var scan: LeftoverScan? {
        uninstallation?.scan
    }

    var appSize: Int64 {
        uninstallation?.appSize ?? 0
    }

    var isAppMeasured: Bool {
        uninstallation?.isAppMeasured ?? true
    }

    var appRequiresPrivileges: Bool {
        uninstallation?.appRequiresPrivileges ?? false
    }

    var isExcluded: Bool {
        uninstallation?.isExcluded ?? false
    }

    var isAppBeyondTheHelper: Bool {
        uninstallation?.isAppBeyondTheHelper ?? false
    }

    /// Known before the scan, so the page says from the start that Peel removes itself in Settings.
    var isPeel: Bool {
        app.isPeelItself
    }

    /// False when the size of something selected is unknown, so the bar shows the sum as "Over" that amount.
    var isSelectionMeasured: Bool {
        (!selectedURLs.contains(app.url) || isAppMeasured) && selectedURLs.allSatisfy { leftoverSizes[$0]?.isMeasured ?? true }
    }

    var selectedSize: Int64 {
        selectedURLs.reduce(0) { $0 + (leftoverSizes[$1]?.size ?? 0) } + (selectedURLs.contains(app.url) ? appSize : 0)
    }

    var isAppRunning: Bool {
        !relatedRunningApps.isEmpty
    }

    var privilegedURLs: Set<URL> { uninstallation?.privilegedURLs ?? [] }

    var requiresHelper: Bool {
        uninstallation?.privilegedURLs.isEmpty == false
    }

    func refresh(installedApps: [InstalledApp], canUseHelper: Bool, casks: [HomebrewPackage] = [], receipts: Set<String> = []) async {
        let app = app
        guard let (result, bundle) = await scanRun.run({
            let result = await Uninstallation.prepare(
                app,
                installedApps: installedApps,
                exclusions: ExclusionsStore.shared.exclusions,
                casks: casks,
                receipts: receipts
            )
            return (result, await Self.look(inside: app))
        }) else { return }
        uninstallation = result
        let leftovers = result.scan.leftovers
        recommended = leftovers.filter(\.match.isRecommended)
        needsReview = leftovers.filter { !$0.match.isRecommended }
        recommendedMovable = result.movable(among: recommended, withApp: true)
        reviewMovable = result.movable(among: needsReview, withApp: false)
        total = result.movable(among: leftovers, withApp: true).size
        leftoverSizes = Dictionary(leftovers.map { ($0.url, ($0.size, $0.isMeasured)) }, uniquingKeysWith: { first, _ in first })
        self.installedApps = installedApps
        (vendorUninstaller, systemExtensions) = bundle
        selectedURLs = result.suggestedSelection(canUseHelper: canUseHelper)
        defaultRoles = await DefaultApps.roles(of: app)
    }

    @concurrent
    private nonisolated static func look(inside app: InstalledApp) async -> (uninstaller: URL?, systemExtensions: [String]) {
        (VendorRemoval.uninstaller(for: app), VendorRemoval.systemExtensions(in: app))
    }

    func removeSelected() async -> TrashResult {
        isRemoving = true
        defer { isRemoving = false }
        let urls = uninstallation?.removalOrder(of: selectedURLs) ?? []
        // These paths are about to hold something else, or nothing, so their cached icons are dropped.
        IconCache.forget(urls)
        return await TrashService(exclusions: ExclusionsStore.shared.exclusions).trash(urls, usingHelperFor: uninstallation?.privilegedURLs ?? [])
    }

    /// Quits the app and the helpers it ships, so nothing rewrites its files while they are removed.
    func quitApp() {
        for running in relatedRunningApps {
            running.terminate()
        }
    }

    private var relatedRunningApps: [NSRunningApplication] {
        RunningCopies.belonging(to: app, among: RunningCopies.current, installedApps: installedApps)
            .compactMap { NSRunningApplication(processIdentifier: $0.identifier) }
    }
}
