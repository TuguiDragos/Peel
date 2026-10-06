import Darwin
public import Foundation

public enum FileAccess {
    /// True when the current user can't move `url` to the Trash without administrator rights.
    public static func requiresPrivilegesToRemove(_ url: URL) -> Bool {
        ParentAccess(url.deletingLastPathComponent()).requiresPrivileges(toRemove: url)
    }

    /// True when macOS's privacy protection, rather than the permissions or a lock, keeps this process from
    /// changing `url`: `access(2)` then fails with `EPERM`, as it does for another developer's app while the process
    /// has no App Management. A lock fails with `EPERM` too, and the permissions with `EACCES`.
    public static func isProtectedByPrivacy(_ url: URL) -> Bool {
        let path = url.path(percentEncoded: false)
        let error = access(path, W_OK) == 0 ? nil : errno
        return isProtectedByPrivacy(accessError: error, isLocked: isLocked(url))
    }

    static func isProtectedByPrivacy(accessError: Int32?, isLocked: Bool) -> Bool {
        accessError == EPERM && !isLocked
    }

    /// Whether `url` is locked (`chflags uchg` or `schg`), which blocks a move whatever the permissions say.
    static func isLocked(_ url: URL) -> Bool {
        var info = stat()
        guard lstat(url.path(percentEncoded: false), &info) == 0 else { return false }
        return info.st_flags & (UInt32(UF_IMMUTABLE) | UInt32(SF_IMMUTABLE)) != 0
    }

    /// True when `url` itself is locked as Finder's Get Info locks it (`UF_IMMUTABLE`, `chflags(2)`): the file
    /// may not be changed until its owner takes the lock off.
    static func isLockedInFinder(_ url: URL) -> Bool {
        var info = stat()
        guard lstat(url.path(percentEncoded: false), &info) == 0 else { return false }
        return info.st_flags & UInt32(UF_IMMUTABLE) != 0
    }
}
