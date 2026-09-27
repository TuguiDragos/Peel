import Darwin
public import Foundation

/// A record of what the helper itself moved to a Trash, and from where. A Put Back request comes from a
/// record that any process running as the user can rewrite, so the helper trusts none of it: it puts back
/// only an item this ledger knows, and only to the place it took it from. The ledger sits in a folder only
/// root can use, outside every folder the helper serves, so the helper can never be asked to move it.
public final class HelperLedger: @unchecked Sendable {
    private struct Entry: Codable {
        let path: String
        let identity: ItemIdentity
        /// The UUID of the volume the item was on. Its device number follows the order volumes mount in, so an
        /// item is known by this and its inode and birth time, and by its device number only when this is missing.
        let volume: String?
        let user: UInt32
        let date: Date

        func names(_ other: ItemIdentity, on otherVolume: String?) -> Bool {
            guard identity.inode == other.inode, identity.birth == other.birth else { return false }
            if let volume, let otherVolume { return volume == otherVolume }
            return identity == other
        }
    }

    public static let defaultFolder = "/private/var/db/\(HelperIdentity.helperIdentifier)"
    public static let defaultURL = URL(filePath: defaultFolder + "/moved.plist")

    private let url: URL
    private let maximumEntries: Int
    /// One lock for every ledger in the process: the helper serves each connection on a queue of its own, and each
    /// request opens the ledger afresh, so a lock of each instance's own would let two requests overwrite each other.
    private static let lock = NSLock()

    /// Returns nil when the folder cannot be made private to the helper. Nothing should be moved then either,
    /// because an item moved without a record cannot be put back.
    public init?(at url: URL = HelperLedger.defaultURL, maximumEntries: Int = 20_000) {
        let folder = url.deletingLastPathComponent().path(percentEncoded: false)
        mkdir(folder, 0o700)
        var info = stat()
        guard
            lstat(folder, &info) == 0, info.st_mode & S_IFMT == S_IFDIR,
            info.st_uid == geteuid(), info.st_mode & 0o077 == 0
        else { return nil }
        self.url = url
        self.maximumEntries = maximumEntries
    }

    /// Records `items` in one write, before any of them moves. Returns false when the write fails, and then
    /// nothing may move. Items are looked up later by identity, so their names in the Trash are not needed.
    public func record(_ items: [OpenItem], movedBy user: uid_t) -> Bool {
        Self.lock.withLock {
            let added = items.compactMap { item in
                item.identity.map { identity in
                    Entry(path: item.path, identity: identity, volume: Self.volume(of: item), user: user, date: .now)
                }
            }
            guard let entries = read() else { return false }
            let kept = entries.filter { entry in !added.contains { entry.names($0.identity, on: $0.volume) } }
            return write((kept + added).suffix(maximumEntries))
        }
    }

    /// Removes `items` from the ledger: those that did not move after all, and those that were put back.
    public func forget(_ items: [OpenItem]) {
        Self.lock.withLock {
            let gone = items.compactMap { item in item.identity.map { ($0, Self.volume(of: item)) } }
            guard !gone.isEmpty, let entries = read() else { return }
            _ = write(entries.filter { entry in !gone.contains { entry.names($0.0, on: $0.1) } })
        }
    }

    /// Moves the folder the ledger lives in to `trash` and returns where it went, or nil when there is none. It is
    /// for Remove Peel, just before the helper goes, since nothing else can move it, and it moves only a folder that
    /// is the helper's own and closed to everyone else, as the ledger keeps its folder.
    public static func moveFolder(_ folder: String = defaultFolder, into trash: DirectoryHandle) -> Result<String?, POSIXError> {
        lock.withLock {
            switch OpenItem.at(folder) {
            case .failure(let error):
                return error.code == .ENOENT ? .success(nil) : .failure(error)
            case .success(let item):
                guard let mode = item.mode, mode & S_IFMT == S_IFDIR, mode & 0o077 == 0, item.owner == geteuid() else {
                    return .failure(POSIXError(.EPERM))
                }
                return TrashMover.move(item, into: trash).map { $0 }
            }
        }
    }

    public struct Unreadable: Error {}

    /// The place `item` was taken from, when this helper took it on behalf of `user`.
    public func origin(of item: OpenItem, movedBy user: uid_t) throws(Unreadable) -> String? {
        guard let entries = Self.lock.withLock({ read() }) else { throw Unreadable() }
        guard let identity = item.identity else { return nil }
        let volume = Self.volume(of: item)
        return entries.last { $0.names(identity, on: volume) && $0.user == user }?.path
    }

    private static func volume(of item: OpenItem) -> String? {
        var info = statfs()
        guard fstatfs(item.parent.descriptor, &info) == 0 else { return nil }
        let mount = withUnsafeBytes(of: info.f_mntonname) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        let volume = URL(filePath: mount, directoryHint: .isDirectory)
        return (try? volume.resourceValues(forKeys: [.volumeUUIDStringKey]))?.volumeUUIDString
    }

    /// The entries, or nil when the ledger is there and cannot be read: then nothing moves and nothing goes back.
    /// A ledger that is not a list of entries is set aside and a new one begins; an entry that makes no sense is
    /// left out.
    private func read() -> [Entry]? {
        var info = stat()
        if lstat(url.path(percentEncoded: false), &info) != 0 {
            return errno == ENOENT ? [] : nil
        }
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let entries = try? PropertyListDecoder().decode([Readable].self, from: data) else {
            return DamagedFile.setAside(url) == nil ? nil : []
        }
        return entries.compactMap(\.entry)
    }

    private struct Readable: Decodable {
        let entry: Entry?

        init(from decoder: any Decoder) throws {
            entry = try? Entry(from: decoder)
        }
    }

    private func write(_ entries: some Sequence<Entry>) -> Bool {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        guard let data = try? encoder.encode(Array(entries)), (try? data.write(to: url, options: .atomic)) != nil else { return false }
        return chmod(url.path(percentEncoded: false), 0o600) == 0
    }
}
