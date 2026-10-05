import Foundation
import Observation
import PeelCore

@Observable
final class BackgroundItemLibrary {
    private(set) var items: [BackgroundItem]?
    /// The kinds of job some of which may be missing, because macOS answered about them in a form Peel cannot read.
    private(set) var unanswered: Set<BackgroundItem.Kind> = []
    /// The scan this page runs, which a newer one or the Stop button ends.
    let scanRun = ScanRun()
    var isScanning: Bool { scanRun.isRunning }
    /// The items with an action in progress. Each is tracked on its own, so one row's action ending never
    /// clears another row's busy state.
    private(set) var runningActionItemIDs: Set<BackgroundItem.ID> = []
    var selection: BackgroundItem.ID?
    /// Actions run on several items at once, so their failures wait their turn rather than replace each other.
    private(set) var failures = AlertQueue<ActionFailure>()

    var selectedItem: BackgroundItem? {
        items?.first { $0.id == selection }
    }

    /// The installed apps passed to the last scan, reused by the rescan after an action. Without them no item
    /// could be traced to the app that owns it.
    private var installedApps: [InstalledApp] = []

    func refresh(installedApps: [InstalledApp]) async {
        self.installedApps = installedApps
        guard
            let result = await scanRun.run({
                await BackgroundItems.scan(installedApps: installedApps, exclusions: ExclusionsStore.shared.exclusions)
            })
        else { return }
        items = result.items
        unanswered = result.unanswered
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
        let label: String
        let action: Action
        let reason: BackgroundItemActions.Failure
        /// The job's file is in the Trash, and `reason` is why launchd still runs the job.
        var fileMoved = false
    }

    func dismissFailure() {
        failures.dismissCurrent()
    }

    /// Runs `action` on `item`, then scans again. What a move to the Trash moved and refused goes to `record` before
    /// the rescan, which can take a while: History is the way back for what just moved.
    func perform(
        _ action: Action, on item: BackgroundItem, recording record: (TrashResult) async -> Void = { _ in }
    ) async {
        runningActionItemIDs.insert(item.id)
        defer { runningActionItemIDs.remove(item.id) }
        do {
            switch action {
            case .start: try await BackgroundItemActions.start(item)
            case .stop: try await BackgroundItemActions.stop(item)
            case .enable: try await BackgroundItemActions.setEnabled(true, for: item)
            case .disable: try await BackgroundItemActions.setEnabled(false, for: item)
            case .moveToTrash:
                let exclusions = ExclusionsStore.shared.exclusions
                let moved = try await QuitGuard.shared.run {
                    () async throws(BackgroundItemActions.Failure) -> BackgroundItemActions.Moved in
                    let moved = try await BackgroundItemActions.moveToTrash(item, exclusions: exclusions)
                    await record(moved.result)
                    return moved
                }
                if let refusal = moved.result.failures.first {
                    failures.add(ActionFailure(label: item.label, action: action, reason: .trash(refusal.reason)))
                }
                if let reason = moved.stillRunning {
                    failures.add(ActionFailure(label: item.label, action: action, reason: reason, fileMoved: true))
                }
            }
        } catch {
            failures.add(ActionFailure(label: item.label, action: action, reason: error))
        }
        await refresh(installedApps: installedApps)
    }
}

extension BackgroundItemLibrary {
    /// What the page says when some jobs may be missing, or nil when macOS answered about every kind.
    var unansweredNote: LocalizedStringResource? {
        switch (unanswered.contains(.agent), unanswered.contains(.daemon)) {
        case (true, true): "macOS didn’t list the agents and daemons that apps added, so some may be missing here."
        case (true, false): "macOS didn’t list the agents that apps added, so some may be missing here."
        case (false, true): "macOS didn’t list the daemons that apps added, so some may be missing here."
        case (false, false): nil
        }
    }
}
