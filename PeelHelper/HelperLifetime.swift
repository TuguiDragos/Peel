import Foundation
import Synchronization

/// Exits the helper after `idleTimeout` seconds with no open connection and no running request.
/// launchd starts it again on the next request.
final class HelperLifetime: Sendable {
    private static let idleTimeout: TimeInterval = 30

    private let state = Mutex((activeConnections: 0, requestsInFlight: 0, generation: 0))

    func start() {
        scheduleExitIfIdle(generation: 0)
    }

    func connectionOpened() {
        state.withLock { state in
            state.activeConnections += 1
            state.generation += 1
        }
    }

    /// Counts a request as running until `requestFinished()`. The connection count alone is not enough: a
    /// client that goes away in the middle of a batch drops it to zero while the work is still running, and
    /// a single `launchctl bootout` can take half a minute.
    func requestStarted() {
        state.withLock { state in
            state.requestsInFlight += 1
            state.generation += 1
        }
    }

    func requestFinished() {
        let generation = state.withLock { state in
            state.requestsInFlight -= 1
            state.generation += 1
            return state.generation
        }
        scheduleExitIfIdle(generation: generation)
    }

    func connectionClosed() {
        let generation = state.withLock { state in
            state.activeConnections -= 1
            state.generation += 1
            return state.generation
        }
        scheduleExitIfIdle(generation: generation)
    }

    /// Schedules an exit in `idleTimeout` seconds, which happens only if the helper is still idle and nothing
    /// has changed since `generation`. The check and the exit happen under one lock, so no connection can open
    /// between them and have its work cut off.
    private func scheduleExitIfIdle(generation: Int) {
        DispatchQueue.global().asyncAfter(deadline: .now() + Self.idleTimeout) {
            self.state.withLock { state in
                if state.activeConnections == 0, state.requestsInFlight == 0, state.generation == generation {
                    // `_exit`, not `exit`: `exit` would first run `atexit` handlers, while the helper's other
                    // threads keep running.
                    _exit(EXIT_SUCCESS)
                }
            }
        }
    }
}
