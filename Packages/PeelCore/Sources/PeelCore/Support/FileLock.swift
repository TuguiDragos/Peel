import Darwin
import Foundation

/// An advisory lock (`flock`) on a `.lock` file beside the file being changed, so a read and the write that
/// follows it are one step for every process and task that goes through here. When the lock file cannot be
/// opened, the change still runs, without the lock.
enum FileLock {
    static func whileHeld<T>(beside url: URL, _ change: () -> T) -> T {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let descriptor = open(url.path(percentEncoded: false) + ".lock", O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { return change() }
        defer { close(descriptor) }
        flock(descriptor, LOCK_EX)
        defer { flock(descriptor, LOCK_UN) }
        return change()
    }
}
