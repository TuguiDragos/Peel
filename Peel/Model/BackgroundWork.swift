import Foundation
import Observation

/// Work that belongs to Peel rather than to its window: watching the folders apps are installed into, and
/// checking for updates while Peel stays open. A task attached to a view is canceled when the view goes away,
/// and Peel can keep running in the menu bar with its window closed, so this work is started once, here,
/// rather than as a view's child task.
@MainActor
@Observable
final class BackgroundWork {
    private var started = false

    /// Starts each piece of work once. Peel keeps one instance for as long as it runs, and a task runs whether or
    /// not its handle is kept, so none is kept: nothing ever cancels them.
    func start(_ work: [@MainActor () async -> Void]) {
        guard !started else { return }
        started = true
        for piece in work {
            Task { await piece() }
        }
    }
}
