import Darwin

/// Waits until the drive holds what was written to a file. `fsync(2)` says a drive may write later data before
/// earlier data, so a record written before a move could be lost in a power cut while the move is kept; `F_FULLFSYNC`
/// (`fcntl(2)`) flushes the drive's queue. A file system that cannot flush it is synced as far as it can be.
public enum DriveFlush {
    public static func file(at path: String) -> Bool {
        let descriptor = open(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }
        return fcntl(descriptor, F_FULLFSYNC) == 0 || fsync(descriptor) == 0
    }
}
