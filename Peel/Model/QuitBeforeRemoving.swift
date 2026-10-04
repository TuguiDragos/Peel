import AppKit
import Observation

/// The processes a removal waits for, since files never move out from under a running app. It asks them to quit,
/// follows them until none runs, and then goes on with the removal. One still open after a while may be waiting for
/// the person, to save their work for example, so forcing it is offered, never done unasked.
@Observable
final class QuitBeforeRemoving {
    /// The processes the alerts name.
    private(set) var running: [NSRunningApplication] = []
    /// Whether the alert that asks to quit them is up.
    var isAsking = false
    /// Whether the alert that offers to force what did not quit is up.
    var isOfferingToForce = false
    /// True from the moment they are asked to quit until none runs or the person gives up.
    private(set) var isWaiting = false
    @ObservationIgnored private var goOn: (() -> Void)?
    @ObservationIgnored private var following: Task<Void, Never>?

    /// How long a quitting app is given before forcing it is offered. An app takes a moment to quit, and one still
    /// open after this is most likely waiting for the person.
    private static let patience: Duration = .seconds(10)

    /// The names of what still runs, for the alerts.
    var names: String {
        running.filter { !$0.isTerminated }.map { $0.localizedName ?? $0.bundleIdentifier ?? "" }
            .formatted(.list(type: .and))
    }

    /// Goes on at once when none of `processes` runs, and otherwise asks the person to quit them first.
    func check(_ processes: [NSRunningApplication], then goOn: @escaping () -> Void) {
        let open = processes.filter { !$0.isTerminated }
        guard !open.isEmpty else { return goOn() }
        running = open
        self.goOn = goOn
        isAsking = true
    }

    /// Asks each process to quit, as Quit in its menu would, and goes on once none runs.
    func quit() {
        running.forEach { $0.terminate() }
        follow()
    }

    /// Ends what did not quit, as Force Quit does: whatever it had not saved is lost.
    func forceQuit() {
        running.filter { !$0.isTerminated }.forEach { $0.forceTerminate() }
        follow()
    }

    /// Stops waiting, and nothing goes on.
    func giveUp() {
        following?.cancel()
        following = nil
        goOn = nil
        isWaiting = false
        isOfferingToForce = false
    }

    private func follow() {
        following?.cancel()
        isWaiting = true
        let processes = running
        following = Task {
            let offer = Task {
                try? await Task.sleep(for: Self.patience)
                guard !Task.isCancelled else { return }
                isOfferingToForce = true
            }
            await Self.untilGone(processes)
            offer.cancel()
            guard !Task.isCancelled else { return }
            isWaiting = false
            isOfferingToForce = false
            let goOn = goOn
            self.goOn = nil
            await Self.untilNoSheet()
            goOn?()
        }
    }

    /// Returns once the sheets on Peel's windows have ended, such as the offer that has just closed. A window shows one
    /// sheet at a time, and one presented while another is still closing can fail to show.
    private static func untilNoSheet() async {
        let ends = NotificationCenter.default.notifications(named: NSWindow.didEndSheetNotification)
        let windows = NSApp.windows.filter { $0.attachedSheet != nil }
        guard !windows.isEmpty else { return }
        for await _ in ends where windows.allSatisfy({ $0.attachedSheet == nil }) {
            return
        }
    }

    /// Returns once every one of `processes` has exited, or the task is canceled. `isTerminated` is followed through
    /// key-value observing, which Apple documents for it, since the workspace does not post a notice for every end.
    static func untilGone(_ processes: [NSRunningApplication]) async {
        let (changes, continuation) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
        let observations = processes.map { $0.observe(\.isTerminated) { _, _ in continuation.yield() } }
        defer { observations.forEach { $0.invalidate() } }
        guard !processes.allSatisfy(\.isTerminated) else { return }
        for await _ in changes where processes.allSatisfy(\.isTerminated) {
            return
        }
    }
}
