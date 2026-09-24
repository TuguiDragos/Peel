import Darwin
public import Foundation

public enum TrashMover {
    /// Renames `item` into `trash` through both folders' descriptors and returns its new path. When the name
    /// is taken, it adds " 2", " 3", and so on, as Finder does. It never copies across volumes and never
    /// resolves a path a second time.
    public static func move(_ item: OpenItem, into trash: DirectoryHandle) -> Result<String, POSIXError> {
        let base = (item.name as NSString).deletingPathExtension
        let pathExtension = (item.name as NSString).pathExtension

        for attempt in 1...1_000 {
            let candidate: String
            if attempt == 1 {
                candidate = item.name
            } else {
                candidate = pathExtension.isEmpty ? "\(base) \(attempt)" : "\(base) \(attempt).\(pathExtension)"
            }
            switch rename(item, to: candidate, in: trash) {
            case .success:
                return .success((trash.path as NSString).appendingPathComponent(candidate))
            case .failure(let error):
                guard error.code == .EEXIST else { return .failure(error) }
            }
        }
        return .failure(POSIXError(.EEXIST))
    }

    /// Renames `item` to `name` in `directory` through both descriptors, refusing to replace anything there.
    public static func rename(_ item: OpenItem, to name: String, in directory: DirectoryHandle) -> Result<Void, POSIXError> {
        let moved = item.name.withCString { from in
            name.withCString { to in
                renameatx_np(item.parent.descriptor, from, directory.descriptor, to, UInt32(RENAME_EXCL))
            }
        }
        guard moved == 0 else { return .failure(.last) }
        return .success(())
    }
}

extension TrashMover {
    /// Moves `items` into `trash` the way the helper does, and returns where each moved path went and why each other
    /// failed, or nil when `ledger` could not record them (then nothing moves). Every item is recorded before any
    /// moves, and only the items that stayed are forgotten again. One request can name an item twice (the same
    /// path, or `/var/...` and `/private/var/...`): it moves once and answers for both paths, since the second try
    /// would fail and forgetting it would also forget the record of the item that moved.
    public static func moveRecorded(
        _ items: [(path: String, item: OpenItem)],
        into trash: DirectoryHandle,
        ledger: HelperLedger,
        movedBy user: uid_t
    ) -> (moved: [String: String], failed: [String: String])? {
        var firstPath: [ItemIdentity: String] = [:]
        var sameAs: [String: String] = [:]
        var unique: [(path: String, item: OpenItem)] = []
        for (path, item) in items {
            if let identity = item.identity {
                if let first = firstPath[identity] {
                    sameAs[path] = first
                    continue
                }
                firstPath[identity] = path
            }
            unique.append((path, item))
        }
        guard ledger.record(unique.map(\.item), movedBy: user) else { return nil }

        var moved: [String: String] = [:]
        var failed: [String: String] = [:]
        var stayed: [OpenItem] = []
        for (path, item) in unique {
            switch move(item, into: trash) {
            case .success(let destination):
                moved[path] = destination
            case .failure(let error):
                failed[path] = error.localizedDescription
                stayed.append(item)
            }
        }
        ledger.forget(stayed)
        for (path, first) in sameAs {
            if let destination = moved[first] {
                moved[path] = destination
            } else if let reason = failed[first] {
                failed[path] = reason
            }
        }
        return (moved, failed)
    }
}
