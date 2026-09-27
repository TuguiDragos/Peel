public import Darwin
public import Foundation

/// A regular file as it was when read: its device and inode, its size, and its times. Writing to the file
/// changes its modification and status change times, so the file read again after a write has a different identity.
public struct FileIdentity: Sendable, Hashable {
    public struct Link: Sendable, Hashable {
        let device: dev_t
        let inode: ino_t

        /// The device and inode of whatever is at `url`, a folder or a link included (a link is not followed).
        /// A move within the same volume keeps them.
        static func of(_ url: URL) -> Link? {
            var info = stat()
            guard lstat(url.path(percentEncoded: false), &info) == 0 else { return nil }
            return Link(device: info.st_dev, inode: info.st_ino)
        }
    }

    let link: Link
    let size: Int64
    let modificationTime: Int
    let statusChangeTime: Int
    let creationTime: Int
    /// Built from the `timespec` fields, since `modificationTime` wraps for a date outside 1677 to 2262.
    let modificationDate: Date

    /// True when both describe the same file with the same contents, even if its metadata changed since.
    /// The status change time is left out: it also moves for `chmod`, `chown`, a rename (`stat(2)`) and an
    /// extended attribute, so adding a tag or opening the file in Finder changes it but not the contents.
    public func holdsTheSameContents(as other: FileIdentity) -> Bool {
        link == other.link && size == other.size && modificationTime == other.modificationTime
            && creationTime == other.creationTime
    }

    public init(_ info: stat) {
        link = Link(device: info.st_dev, inode: info.st_ino)
        size = info.st_size
        modificationTime = Self.nanoseconds(info.st_mtimespec)
        statusChangeTime = Self.nanoseconds(info.st_ctimespec)
        creationTime = Self.nanoseconds(info.st_birthtimespec)
        modificationDate = Date(timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec) + TimeInterval(info.st_mtimespec.tv_nsec) / 1_000_000_000)
    }

    public static func of(_ url: URL) -> FileIdentity? {
        var info = stat()
        guard lstat(url.path(percentEncoded: false), &info) == 0, info.st_mode & S_IFMT == S_IFREG else { return nil }
        return FileIdentity(info)
    }

    /// Nanoseconds since 1970, wrapping instead of trapping. An `Int` of nanoseconds only spans 1677 to 2262,
    /// and these times come from files Peel did not write (a network share can report an unset date as 1601).
    /// The value is only ever compared, so wrapping is safe.
    private static func nanoseconds(_ time: timespec) -> Int {
        time.tv_sec &* 1_000_000_000 &+ time.tv_nsec
    }
}

/// What an item is on the disk: its device and inode while it is there, and its path otherwise. Two spellings of
/// one path, another case on a disk that folds it or a slash at the end, name one item.
enum ItemKey: Hashable {
    case object(FileIdentity.Link)
    case path(String)

    init(_ url: URL) {
        self = FileIdentity.Link.of(url).map(ItemKey.object) ?? .path(PathPattern.comparablePath(of: url))
    }
}
