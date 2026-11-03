import Foundation
@testable import PeelPrivileged
import Synchronization
import Testing

struct HelperLifetimeTests {
    /// Holds each scheduled idle check until the test runs it, so the order is the test's and never the clock's.
    private final class Clock: Sendable {
        private let pending = Mutex<[@Sendable () -> Void]>([])
        let delays = Mutex<[TimeInterval]>([])
        let exits = Mutex(0)

        func lifetime(program: String? = nil) -> HelperLifetime {
            HelperLifetime(
                idleTimeout: 30,
                program: program,
                schedule: { [self] delay, work in
                    delays.withLock { $0.append(delay) }
                    pending.withLock { $0.append(work) }
                },
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
        #expect(clock.delays.withLock { $0 } == [30])
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

    @Test func leavesAsSoonAsItIsIdleOnceAnUpdateReplacedItsProgram() throws {
        let folder = try TemporaryDirectory()
        let program = try folder.file("Peel.app/Contents/MacOS/PeelHelper")
        let update = try folder.file("Update/PeelHelper")
        let clock = Clock()
        let lifetime = clock.lifetime(program: program.path)
        lifetime.start()
        lifetime.connectionOpened()
        #expect(rename(update.path, program.path) == 0)

        lifetime.connectionClosed()

        #expect(clock.delays.withLock { $0 } == [30, 0])
        clock.runChecks()
        #expect(clock.exitCount == 1)
    }

    @Test func leavesAsSoonAsItIsIdleOnceItsProgramIsGone() throws {
        let folder = try TemporaryDirectory()
        let program = try folder.file("Peel.app/Contents/MacOS/PeelHelper")
        let clock = Clock()
        let lifetime = clock.lifetime(program: program.path)
        lifetime.start()
        lifetime.connectionOpened()
        try FileManager.default.removeItem(at: folder.url.appending(path: "Peel.app"))

        lifetime.connectionClosed()

        #expect(clock.delays.withLock { $0 } == [30, 0])
    }

    @Test func waitsWhileItsProgramStaysInPlace() throws {
        let folder = try TemporaryDirectory()
        let program = try folder.file("Peel.app/Contents/MacOS/PeelHelper")
        let clock = Clock()
        let lifetime = clock.lifetime(program: program.path)
        lifetime.start()
        lifetime.connectionOpened()

        lifetime.connectionClosed()

        #expect(clock.delays.withLock { $0 } == [30, 30])
    }
}
