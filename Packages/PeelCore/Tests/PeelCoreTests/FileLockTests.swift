import Darwin
import Foundation
@testable import PeelCore
import Synchronization
import Testing

struct FileLockTests {
    private func isLocked(_ url: URL) -> Bool {
        let descriptor = open(url.path(percentEncoded: false) + ".lock", O_RDWR | O_CLOEXEC)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { return errno == EWOULDBLOCK }
        flock(descriptor, LOCK_UN)
        return false
    }

    @Test func holdsTheLockForTheChangeAndNoLonger() throws {
        let directory = try TemporaryDirectory()
        let url = directory.url.appending(path: "Peel/exclusions.json")

        let heldDuringTheChange = FileLock.whileHeld(beside: url) { isLocked(url) }

        #expect(heldDuringTheChange)
        #expect(!isLocked(url))
        #expect(FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path(percentEncoded: false)))
    }

    @Test func theTerminalCannotStopAProcessThatHoldsTheLock() throws {
        let directory = try TemporaryDirectory()

        let ignored = FileLock.whileHeld(beside: directory.url.appending(path: "Peel/removals.json")) {
            SignalDisposition.isIgnored(SIGTSTP)
        }

        #expect(ignored)
    }

    /// A signal caught while waiting ends `flock` early, with EINTR and without the lock.
    @Test func aSignalWhileWaitingDoesNotLetTheChangeRunUnlocked() throws {
        let directory = try TemporaryDirectory()
        let url = directory.url.appending(path: "Peel/removals.json")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let other = open(url.path(percentEncoded: false) + ".lock", O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
        defer { close(other) }
        #expect(flock(other, LOCK_EX) == 0)
        var action = sigaction()
        action.__sigaction_u.__sa_handler = { _ in }
        var previous = sigaction()
        sigaction(SIGUSR1, &action, &previous)
        defer { sigaction(SIGUSR1, &previous, nil) }

        let state = Mutex<(thread: UInt, released: Bool, ranUnlocked: Bool?)>((0, false, nil))
        let finished = DispatchSemaphore(value: 0)
        Thread {
            // A thread starts with the signals its creator blocks, and the test runner's threads block this one.
            var signals = sigset_t()
            sigemptyset(&signals)
            sigaddset(&signals, SIGUSR1)
            pthread_sigmask(SIG_UNBLOCK, &signals, nil)
            state.withLock { $0.thread = UInt(bitPattern: pthread_self()) }
            FileLock.whileHeld(beside: url) { state.withLock { $0.ranUnlocked = !$0.released } }
            finished.signal()
        }.start()
        Thread.sleep(forTimeInterval: 0.2)
        if let thread = pthread_t(bitPattern: state.withLock { $0.thread }) { pthread_kill(thread, SIGUSR1) }
        Thread.sleep(forTimeInterval: 0.3)
        state.withLock { $0.released = true }
        flock(other, LOCK_UN)

        #expect(finished.wait(timeout: .now() + 5) == .success)
        #expect(state.withLock { $0.ranUnlocked } == false, "the change ran while another held the lock")
    }

    @Test(.permissionsHold) func runsTheChangeWhenNoLockCanBeMade() throws {
        let directory = try TemporaryDirectory()
        try directory.directory("Locked")
        try directory.setPermissions(0o555, of: "Locked")
        defer { try? directory.setPermissions(0o755, of: "Locked") }

        #expect(FileLock.whileHeld(beside: directory.url.appending(path: "Locked/exclusions.json")) { 42 } == 42)
    }
}
