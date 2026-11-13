public import Darwin
import Foundation

/// Where macOS keeps an account's Trash for what is on a disk: `.Trash` in the home folder for what is on the home's
/// disk, and `.Trashes/<uid>` at the top of every other disk, the startup disk too when the home is kept elsewhere.
public enum AccountTrash {
    /// The top of the disk the helper moves on: the one its own folder is on, which everything it moves passes through.
    public static let helpersDisk = top(ofTheDiskOf: (HelperLedger.defaultFolder as NSString).deletingLastPathComponent)
        ?? "/"

    /// The folder `user`'s Trash is for what is on the disk whose top is `top`: `.Trash` in `home` when the home is on
    /// that disk or can't be read, else `.Trashes/<uid>` at the top of the disk.
    public static func folder(for user: uid_t, home: String, onTheDiskAt top: String) -> String {
        guard areOnOneDisk(home, top) == false else { return (home as NSString).appendingPathComponent(".Trash") }
        return (top as NSString).appendingPathComponent(".Trashes/\(user)")
    }

    /// The top of the disk the folder at `path` is on, as the kernel mounts it, which for the startup disk is the top
    /// of its data, `/System/Volumes/Data`. An item's own disk is its folder's: a link may lead to another.
    public static func top(ofTheDiskOf path: String) -> String? {
        var info = statfs()
        guard statfs(path, &info) == 0 else { return nil }
        return withUnsafeBytes(of: info.f_mntonname) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
    }

    /// Whether the folders at `path` and `other` are on one disk, nil when either can't be read. The startup disk's
    /// system and data answer one device number, as macOS's Trash takes them for one disk.
    public static func areOnOneDisk(_ path: String, _ other: String) -> Bool? {
        var one = stat(), two = stat()
        guard stat(path, &one) == 0, stat(other, &two) == 0 else { return nil }
        return one.st_dev == two.st_dev
    }
}
