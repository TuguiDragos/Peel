import Darwin

/// What the account database holds for an account, read into a buffer of its own: `getpwuid` answers in one that
/// every caller shares.
enum AccountRecord {
    /// The text `read` finds in `user`'s entry, or nil when there is no such account or the entry leaves it out.
    static func field(of user: uid_t, _ read: (passwd) -> UnsafeMutablePointer<CChar>?) -> String? {
        var capacity = 1_024
        while capacity <= 65_536 {
            var entry = passwd()
            var found: UnsafeMutablePointer<passwd>?
            var buffer = [CChar](repeating: 0, count: capacity)
            // The entry's fields point into the buffer, which stays pinned only for this call.
            let (result, value) = buffer.withUnsafeMutableBufferPointer { bytes -> (Int32, String?) in
                let result = getpwuid_r(user, &entry, bytes.baseAddress, bytes.count, &found)
                guard result == 0, found != nil, let field = read(entry) else { return (result, nil) }
                return (result, String(cString: field))
            }
            if result == 0 { return value }
            guard result == ERANGE else { return nil }
            capacity *= 4
        }
        return nil
    }
}
