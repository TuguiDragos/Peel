import Foundation

/// The other accounts of this Mac, as their homes show them.
enum OtherAccounts {
    /// Whether a folder in `users` is the home of another account than `uid`: one owned by an account from 501 up,
    /// where macOS numbers the accounts people log in to. `Shared` and hidden names are nobody's home.
    static func exist(
        in users: URL = URL(filePath: "/Users", directoryHint: .isDirectory), besides uid: uid_t = getuid()
    ) -> Bool {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: users.path(percentEncoded: false)) else {
            return false
        }
        return names.contains { name in
            guard !name.hasPrefix("."), name != "Shared" else { return false }
            var info = stat()
            guard lstat(users.appending(path: name).path(percentEncoded: false), &info) == 0,
                  info.st_mode & S_IFMT == S_IFDIR
            else { return false }
            return info.st_uid >= 501 && info.st_uid != uid
        }
    }
}
