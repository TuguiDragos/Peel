import Darwin
import Foundation

/// Whether the user can take an item out of a folder, judged from the folder's permissions and the item's
/// owner. File flags are not read: moving a locked item fails, and the move reports that macOS didn't allow it.
struct ParentAccess {
    let isWritable: Bool
    /// Who owns the folder, when it is sticky.
    let stickyOwner: uid_t?

    init(_ url: URL) {
        let path = url.path(percentEncoded: false)
        var info = stat()
        isWritable = access(path, W_OK) == 0
        stickyOwner = stat(path, &info) == 0 && info.st_mode & S_ISVTX != 0 ? info.st_uid : nil
    }

    func requiresPrivileges(toRemove url: URL) -> Bool {
        guard isWritable else { return true }
        let path = url.path(percentEncoded: false)
        var info = stat()
        guard lstat(path, &info) == 0 else { return false }
        if let stickyOwner,
           Self.stickyFolderKeeps(itemOwnedBy: info.st_uid, folderOwnedBy: stickyOwner, from: getuid()) {
            return true
        }
        if info.st_mode & S_IFMT == S_IFDIR { return access(path, W_OK) != 0 }
        return false
    }

    /// True when a sticky folder keeps `user` from removing the item. Per `man 7 sticky`, only the item's
    /// owner, the folder's owner, or root may remove an item from a sticky folder.
    static func stickyFolderKeeps(itemOwnedBy item: uid_t, folderOwnedBy folder: uid_t, from user: uid_t) -> Bool {
        user != 0 && item != user && folder != user
    }
}
