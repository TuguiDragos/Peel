import Foundation
import PeelCore

/// What `peel uninstall` would do, worked out before anything moves. `--dry-run` prints this plan and a real run
/// moves it, so the two always agree.
struct UninstallPlan {
    struct Item {
        let url: URL
        /// Nil when the size isn't known, as for a folder that didn't answer in time. It is never shown as zero.
        let size: Int64?
        /// Why the item stays, or nil when it moves: the removal guard's answer for the item on disk.
        let refusal: TrashFailure.Reason?
    }

    let app: URL
    /// The bundle first, then the leftovers.
    let items: [Item]
    /// How many recommended leftovers need administrator access. The command line never asks for it, so they stay.
    let needsAdministrator: Int
    /// How many leftovers are listed but not recommended: shared with another app, only possible, or held back for
    /// a reason other than the app's own uninstaller, which removes what it holds back.
    let needsReview: Int
    var uninstallsItself = false
    var makersFolderNames: Set<String> = []

    var moving: [Item] { items.filter { $0.refusal == nil } }
    var staying: [Item] { items.filter { $0.refusal != nil } }
    var total: SizeTotal {
        SizeTotal(movingItemsAt: Dictionary(moving.map { ($0.url, $0.size) }) { first, _ in first })
    }

    /// Why the app itself stays, or nil when it moves. When the app stays, nothing else may move: the files of an
    /// app that is still installed aren't leftovers.
    var appStays: TrashFailure.Reason? { items.first { $0.url == app }?.refusal }

    /// Builds the plan with the bundle first. macOS refuses to move another developer's app without the App
    /// Management permission, and if that refusal came last, the app would stay installed with its settings already
    /// in the Trash.
    static func make(
        _ uninstallation: Uninstallation,
        keepLeftovers: Bool,
        refusal: (URL) -> TrashFailure.Reason?
    ) -> UninstallPlan {
        let app = uninstallation.app.url
        let selection = keepLeftovers ? [app] : uninstallation.suggestedSelection(canUseHelper: false)
        let ordered = [app] + uninstallation.removalOrder(of: selection).filter { $0 != app }
        let leftovers = Dictionary(
            uninstallation.scan.leftovers.map { ($0.url, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        let items = ordered.filter(selection.contains).map { url in
            let leftover = leftovers[url]
            let size = url == app
                ? (uninstallation.isAppMeasured ? uninstallation.appSize : nil)
                : (leftover?.isMeasured == true ? leftover?.size : nil)
            return Item(url: url, size: size, refusal: refusal(url))
        }
        let rest = keepLeftovers ? [] : uninstallation.scan.leftovers
        return UninstallPlan(
            app: app,
            items: items,
            needsAdministrator: rest.count(where: { $0.match.isRecommended && $0.requiresPrivileges }),
            needsReview: rest.count(where: { !$0.match.isRecommended && $0.match.heldBack != .leftToItsUninstaller }),
            uninstallsItself: uninstallation.uninstallsItself != nil,
            makersFolderNames: uninstallation.makersFolderNames
        )
    }

    /// Writes `result` into History, with what the removal guard refused before the move beside what the move
    /// reports, as `Cleanup` does, so `peel history --refused` and the app's Not Moved list it. False when History
    /// could not be written.
    func record(
        _ result: TrashResult,
        from source: String,
        in log: RemovalLog = RemovalLog(),
        refusals: RefusalLog = RefusalLog()
    ) async -> Bool {
        var result = result
        result.failures += staying.compactMap { item in item.refusal.map { TrashFailure(url: item.url, reason: $0) } }
        return await Removals.record(
            result,
            from: source,
            sizes: [URL: Int64](measured: items.map { ($0.url, $0.size) }),
            tool: "applications",
            in: log,
            refusals: refusals
        )
    }

    /// Moves the bundle to the Trash on its own, then the rest only if the bundle really moved. When the app itself
    /// stays, nothing moves.
    func move(using service: TrashService) async -> TrashResult {
        let urls = moving.map(\.url)
        guard urls.contains(app) else { return TrashResult() }
        let files = urls.filter { $0 != app }
        return await service.trash(
            apps: [app],
            thenFiles: { stayed in stayed.isEmpty ? files : [] },
            usingHelperFor: [],
            lettingTheirProgramsRun: uninstallsItself ? [app] : [],
            emptiedFoldersNamed: makersFolderNames
        )
    }
}
