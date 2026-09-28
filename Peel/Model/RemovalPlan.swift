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
    /// The question before a removal, and the removal it starts.
    let question = RemovalQuestion()
    var isRemoving: Bool { question.isRemoving }
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
    private var choices = UninstallSelection()
    /// Whether the helper can act, as last heard, so a scan that lands after it changed selects by what is true now.
    private var canUseHelper = false
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

    var isAppInTheTrash: Bool {
        uninstallation?.isAppInTheTrash ?? false
    }

    /// Known before the scan, so the page says from the start that Peel removes itself in Settings.
    var isPeel: Bool {
        app.isPeelItself
    }

    /// What a confirmation would ask about now: the selection, with the sizes this scan measured.
    var request: RemovalRequest {
        RemovalRequest(urls: selectedURLs, sizes: [URL: Int64](measured: selectedURLs.map { url in
            (url, url == app.url ? (isAppMeasured ? appSize : nil) : leftoverSizes[url].flatMap { $0.isMeasured ? $0.size : nil })
        }))
    }

    var privilegedURLs: Set<URL> { uninstallation?.privilegedURLs ?? [] }

    var requiresHelper: Bool {
        uninstallation?.privilegedURLs.isEmpty == false
    }

    /// What a checkbox can select now.
    var selectable: Set<URL> { choices.selectable }

    /// The revision of the exclusions the last scan read, nil before the first.
    private(set) var exclusionsRevision: Int?

    func refresh(installedApps: [InstalledApp], canUseHelper: Bool, casks: [HomebrewPackage] = [], receipts: Set<String> = []) async {
        self.canUseHelper = canUseHelper
        let app = app
        guard let (result, bundle, revision) = await scanRun.run({
            let revision = ExclusionsStore.shared.revision
            let result = await Uninstallation.prepare(
                app,
                installedApps: installedApps,
                exclusions: ExclusionsStore.shared.exclusions,
                casks: casks,
                receipts: receipts
            )
            return (result, await Self.look(inside: app), revision)
        }) else { return }
        uninstallation = result
        exclusionsRevision = revision
        let leftovers = result.scan.leftovers
        recommended = leftovers.filter(\.match.isRecommended)
        needsReview = leftovers.filter { !$0.match.isRecommended }
        recommendedMovable = result.movable(among: recommended, withApp: true)
        reviewMovable = result.movable(among: needsReview, withApp: false)
        total = result.movable(among: leftovers, withApp: true).size
        leftoverSizes = Dictionary(leftovers.map { ($0.url, ($0.size, $0.isMeasured)) }, uniquingKeysWith: { first, _ in first })
        self.installedApps = installedApps
        (vendorUninstaller, systemExtensions) = bundle
        selectedURLs = choices.update(selectedURLs, in: result, canUseHelper: self.canUseHelper)
        defaultRoles = await DefaultApps.roles(of: app)
    }

    /// Brings the selection in line with the helper as it is now, without scanning again.
    func follow(canUseHelper: Bool) {
        self.canUseHelper = canUseHelper
        guard let uninstallation else { return }
        selectedURLs = choices.update(selectedURLs, in: uninstallation, canUseHelper: canUseHelper)
    }

    @concurrent
    private nonisolated static func look(inside app: InstalledApp) async -> (uninstaller: URL?, systemExtensions: [String]) {
        (VendorRemoval.uninstaller(for: app), VendorRemoval.systemExtensions(in: app))
    }

    /// Moves what `request` asked about, whatever has been selected since.
    func move(_ request: RemovalRequest) async -> TrashResult {
        let urls = uninstallation?.removalOrder(of: request.urls) ?? []
        // These paths are about to hold something else, or nothing, so their cached icons are dropped.
        IconCache.forget(urls)
        return await TrashService(exclusions: ExclusionsStore.shared.exclusions).trash(urls, usingHelperFor: uninstallation?.privilegedURLs ?? [])
    }

    /// The app's processes that run now, the helpers it ships included, which quit before any of its files move.
    var runningProcesses: [NSRunningApplication] {
        RunningCopies.belonging(to: app, among: RunningCopies.current, installedApps: installedApps)
            .compactMap { NSRunningApplication(processIdentifier: $0.identifier) }
    }
}
