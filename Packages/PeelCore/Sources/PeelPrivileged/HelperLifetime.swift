import Foundation
import Synchronization

/// Exits the helper after `idleTimeout` seconds with no open connection and no running request.
/// launchd starts it again on the next request.
public final class HelperLifetime: Sendable {
    private let idleTimeout: TimeInterval
    private let schedule: @Sendable (TimeInterval, @escaping @Sendable () -> Void) -> Void
    private let exit: @Sendable () -> Void
    private let state = Mutex((activeConnections: 0, requestsInFlight: 0, generation: 0))

    public convenience init() {
        self.init(
            idleTimeout: 30,
            schedule: { delay, work in DispatchQueue.global().asyncAfter(deadline: .now() + delay, execute: work) },
            // `_exit`, not `exit`: `exit` would first run `atexit` handlers, while the helper's other threads keep
            // running.
            exit: { _exit(EXIT_SUCCESS) }
        )
    }

    init(
        idleTimeout: TimeInterval,
        schedule: @escaping @Sendable (TimeInterval, @escaping @Sendable () -> Void) -> Void,
        exit: @escaping @Sendable () -> Void
    ) {
        self.idleTimeout = idleTimeout
        self.schedule = schedule
        self.exit = exit
    }

    public func start() {
        scheduleExitIfIdle(generation: 0)
    }

    /// Accepts a connection when `isAllowed` answers yes, and counts it until `connectionClosed()`. It is counted
    /// before `isAllowed` is asked, since that can take a while and the helper must not exit meanwhile.
    public func accept(_ isAllowed: () -> Bool) -> Bool {
        state.withLock { state in
            state.activeConnections += 1
            state.generation += 1
        }
        guard isAllowed() else {
            connectionClosed()
            return false
        }
        return true
    }

    /// Counts a request as running until `requestFinished()`. The connection count alone is not enough: a
    /// client that goes away in the middle of a batch drops it to zero while the work is still running, and
    /// a single `launchctl bootout` can take half a minute.
    public func requestStarted() {
        state.withLock { state in
            state.requestsInFlight += 1
            state.generation += 1
        }
    }

    public func requestFinished() {
        let generation = state.withLock { state in
            state.requestsInFlight -= 1
            state.generation += 1
            return state.generation
        }
        scheduleExitIfIdle(generation: generation)
    }

    public func connectionClosed() {
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
        schedule(idleTimeout) { [self] in
            state.withLock { state in
                if state.activeConnections == 0, state.requestsInFlight == 0, state.generation == generation {
                    exit()
                }
            }
        }
    }
}
