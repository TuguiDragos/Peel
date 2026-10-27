import Foundation
import Observation
import PeelCore
import SwiftUI

@Observable
final class BackgroundItemLibrary {
    private(set) var items: [BackgroundItem]?
    /// The kinds of job some of which may be missing, because macOS answered about them in a form Peel cannot read.
    private(set) var unanswered = BackgroundItems.Unanswered()
    /// The folders that kept Peel from listing a folder of job files.
    private(set) var unreadableFolders: [URL] = []
    /// The scan this page runs, which a newer one or the Stop button ends.
    let scanRun = ScanRun()
    var isScanning: Bool { scanRun.isRunning }
    /// Counts the scans that finished, so an item's page asks macOS about it again with each.
    private(set) var scans = 0
    /// The items with an action in progress. Each is tracked on its own, so one row's action ending never
    /// clears another row's busy state.
    private(set) var runningActionItemIDs: Set<BackgroundItem.ID> = []
    var selection: BackgroundItem.ID?
    /// Actions run on several items at once, so what each has to say waits its turn rather than replace another.
    private(set) var alerts = AlertQueue<ActionAlert>()

    var selectedItem: BackgroundItem? {
        items?.first { $0.id == selection }
    }

    /// The installed apps passed to the last scan, reused by the rescan after an action. Without them no item
    /// could be traced to the app that owns it.
    private var installedApps: [InstalledApp] = []
    private let scan: @MainActor ([InstalledApp], Exclusions) async -> BackgroundItems.Scan
    /// The reads of the list started so far, so that a job just enabled is judged by a read started after it.
    private var readsStarted = 0
    private var enabledJobs: [(job: BackgroundItem, readsBefore: Int)] = []

    init(
        scan: @escaping @MainActor ([InstalledApp], Exclusions) async -> BackgroundItems.Scan = {
            await BackgroundItems.scan(installedApps: $0, exclusions: $1)
        }
    ) {
        self.scan = scan
    }

    func refresh(installedApps: [InstalledApp]) async {
        self.installedApps = installedApps
        readsStarted += 1
        let read = readsStarted
        let scan = scan
        guard
            let result = await scanRun.run({ await scan(installedApps, ExclusionsStore.shared.exclusions) })
        else { return }
        show(result, read: read)
    }

    /// Reads the list again without showing a scan, once it has been read: System Settings and other apps change what
    /// launchd runs. Never while an action runs, whose own scan follows it.
    func readAgain(installedApps: [InstalledApp]) async {
        guard items != nil, runningActionItemIDs.isEmpty else { return }
        self.installedApps = installedApps
        readsStarted += 1
        let read = readsStarted
        let scan = scan
        guard
            let result = await scanRun.runQuietly({ await scan(installedApps, ExclusionsStore.shared.exclusions) }),
            runningActionItemIDs.isEmpty
        else { return }
        show(result, read: read)
    }

    /// Notes a job just enabled. The first read of the list started after now says whether it left the list, whoever
    /// asked for that read: the action's own scan may be overtaken by another.
    func noteEnabled(_ item: BackgroundItem) {
        enabledJobs.append((item, readsStarted))
    }

    private func show(_ result: BackgroundItems.Scan, read: Int) {
        items = result.items
        unanswered = result.unanswered
        unreadableFolders = result.unreadableFolders
        scans += 1
        if let selection, items?.contains(where: { $0.id == selection }) != true {
            self.selection = nil
        }
        let judged = enabledJobs.filter { $0.readsBefore < read }.map(\.job)
        enabledJobs.removeAll { $0.readsBefore < read }
        for job in judged {
            if let alert = Self.alertAfterEnabling(job, listed: items) {
                alerts.add(alert)
            }
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

    /// What the list says after an action: why it failed, or that an enabled job left the list until macOS loads it.
    enum ActionAlert {
        case failed(ActionFailure)
        case enabledUntilLoaded(label: String, kind: BackgroundItem.Kind)
    }

    func dismissAlert() {
        alerts.dismissCurrent()
    }

    /// What VoiceOver hears once an action on `item` is done and the list read again: the state it is in now, which
    /// its badge shows without a word, or nil when it left the list.
    static func announcement(for item: BackgroundItem, in listed: [BackgroundItem]?) -> AttributedString? {
        guard let now = listed?.first(where: { $0.id == item.id }) else { return nil }
        return AttributedString(localized: "\(now.label): \(String(localized: now.stateWords()))")
    }

    /// A job enabled while launchd doesn't have it leaves the list, since it is listed only while disabled or loaded.
    static func alertAfterEnabling(_ item: BackgroundItem, listed: [BackgroundItem]?) -> ActionAlert? {
        guard let listed, !listed.contains(where: { $0.id == item.id }) else { return nil }
        return .enabledUntilLoaded(label: item.label, kind: item.kind)
    }

    /// Runs `action` on `item`, then scans again. What a move to the Trash moved and refused goes to `record` before
    /// the rescan, which can take a while: History is the way back for what just moved.
    func perform(
        _ action: Action, on item: BackgroundItem, recording record: (TrashResult) async -> Void = { _ in }
    ) async {
        runningActionItemIDs.insert(item.id)
        defer { runningActionItemIDs.remove(item.id) }
        var failed = false
        do {
            switch action {
            case .start: try await BackgroundItemActions.start(item)
            case .stop: try await BackgroundItemActions.stop(item)
            case .enable:
                try await BackgroundItemActions.setEnabled(true, for: item)
                noteEnabled(item)
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
                    let failure = ActionFailure(label: item.label, action: action, reason: .trash(refusal.reason))
                    alerts.add(.failed(failure))
                }
                if let reason = moved.stillRunning {
                    let failure = ActionFailure(label: item.label, action: action, reason: reason, fileMoved: true)
                    alerts.add(.failed(failure))
                }
            }
        } catch {
            failed = true
            alerts.add(.failed(ActionFailure(label: item.label, action: action, reason: error)))
        }
        let shown = scans
        await refresh(installedApps: installedApps)
        // History tells of a move to the Trash, and an alert of a failure.
        if action != .moveToTrash, !failed, scans > shown, let words = Self.announcement(for: item, in: items) {
            AccessibilityNotification.Announcement(words).post()
        }
    }
}

extension BackgroundItemLibrary {
    /// What the page says when some jobs may be missing, a paragraph for each reason, or nil when none is.
    var missingNote: String? {
        let parts = (unanswered.lists.missingJobsNote.map { [String(localized: $0)] } ?? [])
            + (unanswered.overrides.isEmpty ? [] : [
                String(localized: "macOS didn’t say which jobs are disabled, so Peel can’t tell whether they run, and a disabled one may be missing here."),
            ])
            + (unanswered.jobs.isEmpty ? [] : [
                String(localized: "macOS didn’t answer for some jobs that apps added, so they may be missing here."),
            ])
            + unreadableFolders.map {
                String(localized: "Peel can’t look in \($0.abbreviatedPath), so a job whose file is there shows here only while macOS has it loaded.")
            }
        return parts.isEmpty ? nil : parts.joined(separator: "\n\n")
    }
}

extension Set<BackgroundItem.Kind> {
    /// What a page says when jobs of these kinds may be missing from it, or nil when there are none.
    var missingJobsNote: LocalizedStringResource? {
        switch (contains(.agent), contains(.daemon)) {
        case (true, true): "macOS didn’t list the agents and daemons that apps added, so some may be missing here."
        case (true, false): "macOS didn’t list the agents that apps added, so some may be missing here."
        case (false, true): "macOS didn’t list the daemons that apps added, so some may be missing here."
        case (false, false): nil
        }
    }
}
