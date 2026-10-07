import Darwin
import Foundation

/// An advisory lock (`flock`) on a `.lock` file beside the file being changed, so a read and the write that
/// follows it are one step for every process and task that goes through here. When the lock file cannot be
/// opened or locked, the change still runs, without the lock.
enum FileLock {
    /// While a process waits for a lock or holds it, the terminal cannot stop it (Ctrl-Z): stopped there, it would
    /// keep every other process that needs the file waiting until it went on.
    private static let unstoppable = IgnoredSignals([SIGTSTP])

    static func whileHeld<T>(beside url: URL, _ change: () -> T) -> T {
        guard let descriptor = openLock(beside: url) else { return change() }
        defer { close(descriptor) }
        return unstoppable.run {
            let locked = lock(descriptor)
            defer { if locked { flock(descriptor, LOCK_UN) } }
            return change()
        }
    }

    /// The same, for a change that has to wait for other work, such as a move to the Trash.
    static func whileHeld<T>(beside url: URL, waitingFor change: () async -> T) async -> T {
        guard let descriptor = openLock(beside: url) else { return await change() }
        defer { close(descriptor) }
        return await unstoppable.run {
            let locked = lock(descriptor)
            defer { if locked { flock(descriptor, LOCK_UN) } }
            return await change()
        }
    }

    private static func openLock(beside url: URL) -> Int32? {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let descriptor = open(url.path(percentEncoded: false) + ".lock", O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
        return descriptor >= 0 ? descriptor : nil
    }

    private static func lock(_ descriptor: Int32) -> Bool {
        // A signal caught while waiting ends the wait early (EINTR), without the lock.
        var locked = flock(descriptor, LOCK_EX)
        while locked != 0, errno == EINTR {
            locked = flock(descriptor, LOCK_EX)
        }
        return locked == 0
    }
}
