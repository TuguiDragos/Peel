import Accessibility
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
    /// The options of the removal, kept here rather than in the page, so a click updates only the option's own row.
    var resetsPrivacy = false
    var removesDockTile = true
    /// The kinds of files and links this app opens by default, so the page can say which app opens them once
    /// it is gone.
    private(set) var defaultRoles: [DefaultRole] = []
    /// Every installed app as of the last scan. It tells this app's running helpers apart from another app's.
    private var installedApps: [InstalledApp] = []
    /// Read from the bundle once per scan, off the main actor. The page reads it on every checkbox change, and
    /// finding the uninstaller lists whole folders, such as Applications.
    private(set) var vendorUninstaller: URL?
    /// Read once per scan as well, so Rescan shows them as they are now: whether the Dock holds a tile for the app,
    /// and the receipts of the packages that installed it, with what each put outside the app.
    private(set) var hasDockTile = false
    private(set) var packageReceipts: [PackageReceipt] = []
    private(set) var filesOutside: [PackageReceipt.ID: [PackageReceipt.Item]] = [:]
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

    private let jobsKeptRunning: @Sendable ([URL]) async -> Set<pid_t>
    private let systemExtensions: AppExtensions.SystemExtensionsAnswer

    init(
        app: InstalledApp,
        jobsKeptRunning: @escaping @Sendable ([URL]) async -> Set<pid_t> = {
            await RunningCopies.keptRunningByJobs(inside: $0)
        },
        systemExtensions: @escaping AppExtensions.SystemExtensionsAnswer = AppExtensions.askingMacOS
    ) {
        self.app = app
        self.jobsKeptRunning = jobsKeptRunning
        self.systemExtensions = systemExtensions
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

    var appSharesStorage: Bool {
        uninstallation?.appSharesStorage ?? false
    }

    var appRequiresPrivileges: Bool {
        uninstallation?.appRequiresPrivileges ?? false
    }

    /// Read from the exclusions, not the scan, so it holds from the first frame and as soon as they change.
    var isExcluded: Bool {
        ExclusionsStore.shared.exclusions.excludes(app)
    }

    /// The app's other copies that stay installed, which share its privacy permissions.
    var otherCopies: [URL] {
        uninstallation?.otherCopies ?? []
    }

    var mayResetPrivacy: Bool {
        let exclusions = ExclusionsStore.shared.exclusions
        return exclusions.isKnown && !exclusions.excludes(app)
    }

    /// Resets the app's privacy permissions, as asked from its page, and tells VoiceOver how it went in the words the
    /// page shows: they appear under the buttons, away from the menu the reset was asked from.
    func resetPrivacy(
        resetting: (InstalledApp) async -> PrivacyReset.Result = { await PrivacyReset.reset($0) },
        announcing: (AttributedString) -> Void = { AccessibilityNotification.Announcement($0).post() }
    ) async -> PrivacyReset.Result {
        let result = await resetting(app)
        announcing(AttributedString(localized: result.outcome(for: app.name)))
        return result
    }

    var isAppBeyondTheHelper: Bool {
        uninstallation?.isAppBeyondTheHelper ?? false
    }

    var isAppInTheTrash: Bool {
        uninstallation?.isAppInTheTrash ?? false
    }

    /// From the app before the scan, and from the system extensions macOS installed once the scan has asked.
    var removedElsewhere: RemovedElsewhere? {
        uninstallation?.removedElsewhere ?? app.removedElsewhere
    }

    /// What a confirmation would ask about now: the selection, with the sizes this scan measured.
    var request: RemovalRequest {
        RemovalRequest(
            urls: selectedURLs,
            sizes: [URL: Int64](measured: selectedURLs.map { url in
                (
                    url,
                    url == app.url
                        ? (isAppMeasured ? appSize : nil)
                        : leftoverSizes[url].flatMap { $0.isMeasured ? $0.size : nil }
                )
            }),
            sharingStorage: appSharesStorage ? [app.url] : []
        )
    }

    var privilegedURLs: Set<URL> { uninstallation?.privilegedURLs ?? [] }

    var helperUse: Uninstallation.HelperUse? { uninstallation?.helperUse(receipts: packageReceipts.count) }

    /// What a checkbox can select now.
    var selectable: Set<URL> { choices.selectable }

    var appStays: Bool {
        uninstallation?.appStays(canUseHelper: canUseHelper) ?? false
    }

    func selectableRows(_ rows: [URL]) -> SelectableRows<URL> {
        uninstallation?.selectableRows(rows, canUseHelper: canUseHelper)
            ?? SelectableRows(rows: rows, selectable: [], recommended: [])
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
        let app = app
        let systemExtensions = systemExtensions
        guard let (result, bundle, installed, revision, roles, isInTheDock) = await scanRun.run({
            let revision = ExclusionsStore.shared.revision
            let exclusions = ExclusionsStore.shared.exclusions
            async let roles = DefaultApps.roles(of: app)
            async let isInTheDock = !(await DockTiles().holding([app.url])).isEmpty
            // The uninstall and the page ask `pkgutil` about the same app.
            let answers = PackageReceipts.Answers()
            let result = await Uninstallation.prepare(
                app,
                installedApps: installedApps,
                exclusions: exclusions,
                casks: casks,
                receipts: receipts,
                systemExtensions: systemExtensions,
                answers: answers
            )
            return (
                result,
                await Self.look(inside: app),
                await Self.packageReceipts(of: app, exclusions: exclusions, answers: answers),
                revision,
                await roles,
                await isInTheDock
            )
        }) else { return }
        uninstallation = result
        exclusionsRevision = revision
        let leftovers = result.scan.leftovers
        recommended = leftovers.filter(\.match.isRecommended)
        needsReview = leftovers.filter { !$0.match.isRecommended }
        countMovable(in: result)
        leftoverSizes = Dictionary(
            leftovers.map { ($0.url, ($0.size, $0.isMeasured)) },
            uniquingKeysWith: { first, _ in first }
        )
        self.installedApps = installedApps
        vendorUninstaller = bundle
        (packageReceipts, filesOutside) = installed
        selectedURLs = choices.update(selectedURLs, in: result, canUseHelper: self.canUseHelper)
        defaultRoles = roles
        hasDockTile = isInTheDock
    }

    /// Asks macOS again about the app's system extensions, which the person turns on and off in System Settings, and
    /// brings the page in line with the answer without scanning its files again.
    func followSystemExtensions() async {
        guard uninstallation != nil else { return }
        let carried = await AppExtensions.installed(carriedBy: app, asking: systemExtensions)
        guard var current = uninstallation, carried != current.installedSystemExtensions, question.mayScan() else {
            return
        }
        current.installedSystemExtensions = carried
        uninstallation = current
        selectedURLs = choices.update(selectedURLs, in: current, canUseHelper: canUseHelper)
        countMovable(in: current)
    }

    /// Brings the selection in line with the helper as it is now, without scanning again.
    func follow(canUseHelper: Bool) {
        self.canUseHelper = canUseHelper
        guard let uninstallation else { return }
        selectedURLs = choices.update(selectedURLs, in: uninstallation, canUseHelper: canUseHelper)
        countMovable(in: uninstallation)
    }

    private func countMovable(in result: Uninstallation) {
        recommendedMovable = result.movable(among: recommended, withApp: true, canUseHelper: canUseHelper)
        reviewMovable = result.movable(among: needsReview, withApp: false, canUseHelper: canUseHelper)
        total = result.movable(among: result.scan.leftovers, withApp: true, canUseHelper: canUseHelper).size
    }

    /// What each package put outside the app is worked out here, off the main actor, because it takes an `lstat` per
    /// file and the page is redrawn whenever a checkbox changes.
    @concurrent
    private nonisolated static func packageReceipts(
        of app: InstalledApp,
        exclusions: Exclusions,
        answers: PackageReceipts.Answers
    ) async -> ([PackageReceipt], [PackageReceipt.ID: [PackageReceipt.Item]]) {
        let receipts = await PackageReceipts.receipts(installing: app.url, exclusions: exclusions, answers: answers)
        let files = receipts.map {
            ($0.id, VendorRemoval.filesOutsideBundle(of: $0, app: app, otherReceipts: receipts))
        }
        return (receipts, Dictionary(files, uniquingKeysWith: { first, _ in first }))
    }

    @concurrent
    private nonisolated static func look(inside app: InstalledApp) async -> URL? {
        VendorRemoval.uninstaller(for: app)
    }

    /// Moves what `request` asked about with `service`, whatever has been selected since.
    func move(_ request: RemovalRequest, using service: TrashService) async -> TrashResult {
        guard let uninstallation else { return TrashResult() }
        // These paths are about to hold something else, or nothing, so their cached icons are dropped.
        IconCache.forget(uninstallation.removalOrder(of: request.urls))
        return await uninstallation.move(request.urls, using: service)
    }

    /// The app's processes that run now and quit before any of its files move, the helpers it ships included
    /// (`RunningCopies.toQuit`).
    func processesToQuit() async -> [NSRunningApplication] {
        await RunningCopies.toQuit(
            beforeMoving: app, among: RunningCopies.current, installedApps: installedApps, keptByJobs: jobsKeptRunning
        ).compactMap { NSRunningApplication(processIdentifier: $0.identifier) }
    }
}
