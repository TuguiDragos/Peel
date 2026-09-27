import Foundation
import Observation
import PeelCore

@Observable
final class BackgroundItemLibrary {
    private(set) var items: [BackgroundItem]?
    /// The scan this page runs, which a newer one or the Stop button ends.
    let scanRun = ScanRun()
    var isScanning: Bool { scanRun.isRunning }
    /// The items with an action in progress. Each is tracked on its own, so one row's action ending never
    /// clears another row's busy state.
    private(set) var runningActionItemIDs: Set<BackgroundItem.ID> = []
    var selection: BackgroundItem.ID?
    var failure: ActionFailure?

    var selectedItem: BackgroundItem? {
        items?.first { $0.id == selection }
    }

    /// The installed apps passed to the last scan, reused by the rescan after an action. Without them no item
    /// could be traced to the app that owns it.
    private var installedApps: [InstalledApp] = []

    func refresh(installedApps: [InstalledApp]) async {
        self.installedApps = installedApps
        guard let result = await scanRun.run({ await BackgroundItems.scan(installedApps: installedApps, exclusions: ExclusionsStore.shared.exclusions) }) else { return }
        items = result
        if let selection, items?.contains(where: { $0.id == selection }) != true {
            self.selection = nil
        }
    }

    enum Action {
        case start
        case stop
        case enable
        case disable
        case moveToTrash
    }

    struct ActionFailure {
        let action: Action
        let reason: BackgroundItemActions.Failure
    }

    @discardableResult
    func perform(_ action: Action, on item: BackgroundItem) async -> TrashResult {
        runningActionItemIDs.insert(item.id)
        defer { runningActionItemIDs.remove(item.id) }
        var result = TrashResult()
        do {
            switch action {
            case .start: try await BackgroundItemActions.start(item)
            case .stop: try await BackgroundItemActions.stop(item)
            case .enable: try await BackgroundItemActions.setEnabled(true, for: item)
            case .disable: try await BackgroundItemActions.setEnabled(false, for: item)
            case .moveToTrash:
                result = try await BackgroundItemActions.moveToTrash(item, exclusions: ExclusionsStore.shared.exclusions)
                if let refusal = result.failures.first {
                    failure = ActionFailure(action: action, reason: .trash(refusal.reason))
                }
            }
        } catch {
            failure = ActionFailure(action: action, reason: error)
        }
        await refresh(installedApps: installedApps)
        return result
    }
}
