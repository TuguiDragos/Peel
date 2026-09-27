import Foundation
@testable import PeelPrivileged
import Synchronization
import Testing

struct HelperLifetimeTests {
    /// Holds each scheduled idle check until the test runs it, so the order is the test's and never the clock's.
    private final class Clock: Sendable {
        private let pending = Mutex<[@Sendable () -> Void]>([])
        let exits = Mutex(0)

        func lifetime() -> HelperLifetime {
            HelperLifetime(
                idleTimeout: 30,
                schedule: { [self] _, work in pending.withLock { $0.append(work) } },
                exit: { [self] in exits.withLock { $0 += 1 } }
            )
        }

        func runChecks() {
            let due = pending.withLock { pending in
                defer { pending = [] }
                return pending
            }
            due.forEach { $0() }
        }

        var exitCount: Int { exits.withLock { $0 } }
    }

    @Test func exitsWhenNothingHappensAfterItStarts() {
        let clock = Clock()
        clock.lifetime().start()
        clock.runChecks()
        #expect(clock.exitCount == 1)
    }

    @Test func staysWhileARequestRunsAndExitsAfterIt() {
        let clock = Clock()
        let lifetime = clock.lifetime()
        lifetime.start()
        lifetime.requestStarted()
        clock.runChecks()
        #expect(clock.exitCount == 0)

        lifetime.requestFinished()
        clock.runChecks()
        #expect(clock.exitCount == 1)
    }

    @Test func staysWhileAConnectionIsBeingAccepted() {
        let clock = Clock()
        let lifetime = clock.lifetime()
        lifetime.start()

        let accepted = lifetime.accept {
            clock.runChecks()
            return true
        }

        #expect(accepted)
        #expect(clock.exitCount == 0, "the helper exited while it was accepting a connection")
        lifetime.connectionClosed()
        clock.runChecks()
        #expect(clock.exitCount == 1)
    }

    @Test func aRefusedConnectionLeavesTheHelperFreeToExit() {
        let clock = Clock()
        let lifetime = clock.lifetime()
        lifetime.start()

        let accepted = lifetime.accept {
            clock.runChecks()
            return false
        }

        #expect(!accepted)
        #expect(clock.exitCount == 0, "the helper exited while it was asking about a connection")
        clock.runChecks()
        #expect(clock.exitCount == 1, "a refused connection kept the helper running")
    }
}
