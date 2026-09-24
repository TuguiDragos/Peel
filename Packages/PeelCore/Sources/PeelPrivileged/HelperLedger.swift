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
        let user: UInt32
        let date: Date
    }

    public static let defaultURL = URL(filePath: "/private/var/db/\(HelperIdentity.helperIdentifier)/moved.plist")

    private let url: URL
    private let maximumEntries: Int
    private let lock = NSLock()

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
        lock.withLock {
            let added = items.compactMap { item in
                item.identity.map { Entry(path: item.path, identity: $0, user: user, date: .now) }
            }
            let known = Set(added.map(\.identity))
            return write((read().filter { !known.contains($0.identity) } + added).suffix(maximumEntries))
        }
    }

    /// Removes `items` from the ledger: those that did not move after all, and those that were put back.
    public func forget(_ items: [OpenItem]) {
        lock.withLock {
            let gone = Set(items.compactMap(\.identity))
            guard !gone.isEmpty else { return }
            _ = write(read().filter { !gone.contains($0.identity) })
        }
    }

    /// The place `item` was taken from, when this helper took it on behalf of `user`.
    public func origin(of item: OpenItem, movedBy user: uid_t) -> String? {
        lock.withLock {
            guard let identity = item.identity else { return nil }
            return read().last { $0.identity == identity && $0.user == user }?.path
        }
    }

    private func read() -> [Entry] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? PropertyListDecoder().decode([Entry].self, from: data)) ?? []
    }

    private func write(_ entries: some Sequence<Entry>) -> Bool {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        guard let data = try? encoder.encode(Array(entries)), (try? data.write(to: url, options: .atomic)) != nil else { return false }
        return chmod(url.path(percentEncoded: false), 0o600) == 0
    }
}
