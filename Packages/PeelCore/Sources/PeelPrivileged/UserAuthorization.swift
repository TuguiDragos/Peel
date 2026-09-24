public import Darwin
private import Darwin.membership

/// Decides who the helper works for. Its Mach service is advertised in the system domain, so every account
/// on the Mac can reach it, including a standard account or a second one logged in at the same time. What
/// it does, such as moving files inside `/Library`, belongs to root alone, so it answers only the accounts
/// macOS trusts with administration, and refuses whenever that cannot be established.
public enum UserAuthorization {
    private static let administratorsGroup = "admin"

    /// True when `user` is in the `admin` group. `mbr_check_membership(3)` says to use it rather than
    /// `getgrouplist(2)`: it asks Open Directory and counts membership through nested groups. It also needs
    /// neither `getpwuid` nor `getgrnam`, whose shared return buffer this daemon cannot rely on while it
    /// answers more than one connection.
    public static func isAdministrator(_ user: uid_t) -> Bool {
        var account = uuid_t(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
        var administrators = uuid_t(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
        guard
            mbr_uid_to_uuid(user, &account.0) == 0,
            mbr_identifier_to_uuid(ID_TYPE_GROUPNAME, administratorsGroup, administratorsGroup.utf8.count, &administrators.0) == 0
        else { return false }

        var isMember: Int32 = 0
        guard mbr_check_membership(&account.0, &administrators.0, &isMember) == 0 else { return false }
        return isMember != 0
    }

    /// The account's home folder, read into a buffer of its own so two connections cannot overwrite each
    /// other's answer the way `getpwuid` would.
    public static func homeDirectory(of user: uid_t) -> String? {
        var capacity = 1_024
        while capacity <= 65_536 {
            var entry = passwd()
            var found: UnsafeMutablePointer<passwd>?
            var buffer = [CChar](repeating: 0, count: capacity)
            // `pw_dir` points into the buffer, and a pointer bridged from an array is only good for the call it
            // was made for. The string is read while the buffer is still pinned.
            let (result, directory) = buffer.withUnsafeMutableBufferPointer { bytes -> (Int32, String?) in
                let result = getpwuid_r(user, &entry, bytes.baseAddress, bytes.count, &found)
                guard result == 0, found != nil, let directory = entry.pw_dir else { return (result, nil) }
                return (result, String(cString: directory))
            }
            if result == 0 { return directory }
            guard result == ERANGE else { return nil }
            capacity *= 4
        }
        return nil
    }
}
