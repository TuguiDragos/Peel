import Darwin
import Foundation

/// Who owns a folder, its group, and its mode, as `stat(2)` gives them.
struct FolderPermissions: Equatable {
    let owner: uid_t
    let group: gid_t
    let mode: mode_t

    /// Whether the mode lets `account` write here, as the kernel checks it: the owner's bits for the owner, the
    /// group's for a member of the group, the others' for anyone else.
    func lets(_ account: uid_t, write isInGroup: (gid_t) -> Bool) -> Bool {
        if account == owner { return mode & S_IWUSR != 0 }
        return mode & (isInGroup(group) ? S_IWGRP : S_IWOTH) != 0
    }
}

extension FolderPermissions {
    init?(of url: URL, followingALink: Bool) {
        var info = stat()
        let path = url.path(percentEncoded: false)
        guard (followingALink ? stat(path, &info) : lstat(path, &info)) == 0 else { return nil }
        self.init(owner: info.st_uid, group: info.st_gid, mode: info.st_mode)
    }
}

/// What Open Directory says of the groups an account is in, asked with `mbr_check_membership(3)`, which counts
/// membership through nested groups, as `UserAuthorization.isAdministrator` asks it.
enum GroupMembership {
    static func isMember(_ user: uid_t, of group: gid_t) -> Bool {
        var account = uuid()
        var members = uuid()
        guard mbr_uid_to_uuid(user, &account) == 0, mbr_gid_to_uuid(group, &members) == 0 else { return false }
        var isMember: Int32 = 0
        return mbr_check_membership(&account, &members, &isMember) == 0 && isMember != 0
    }

    /// Room for a `uuid_t`, as an array, since an array passed in-out is a pointer to all of its storage.
    private static func uuid() -> [UInt8] {
        [UInt8](repeating: 0, count: MemoryLayout<uuid_t>.size)
    }
}
