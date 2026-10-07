import Darwin
public import Foundation

public enum TrashMover {
    /// Renames `item` into `trash` through both folders' descriptors and returns its new path. When the name
    /// is taken, it adds " 2", " 3", and so on, as Finder does. It never copies across volumes and never
    /// resolves a path a second time.
    public static func move(_ item: OpenItem, into trash: DirectoryHandle) -> Result<String, POSIXError> {
        move(item, into: trash, exclusively: renameExclusively)
    }

    static func move(
        _ item: OpenItem,
        into trash: DirectoryHandle,
        exclusively: ExclusiveRename
    ) -> Result<String, POSIXError> {
        let base = (item.name as NSString).deletingPathExtension
        let pathExtension = (item.name as NSString).pathExtension

        for attempt in 1...1_000 {
            let candidate: String
            if attempt == 1 {
                candidate = item.name
            } else {
                candidate = pathExtension.isEmpty ? "\(base) \(attempt)" : "\(base) \(attempt).\(pathExtension)"
            }
            switch rename(item, to: candidate, in: trash, exclusively: exclusively) {
            case .success:
                return .success((trash.path as NSString).appendingPathComponent(candidate))
            case .failure(let error):
                guard error.code == .EEXIST else { return .failure(error) }
            }
        }
        return .failure(POSIXError(.EEXIST))
    }

    /// Renames `item` to `name` in `directory` through both descriptors, refusing to replace anything there.
    public static func rename(
        _ item: OpenItem,
        to name: String,
        in directory: DirectoryHandle
    ) -> Result<Void, POSIXError> {
        rename(item, to: name, in: directory, exclusively: renameExclusively)
    }

    /// A rename that refuses to replace what is at the new name. A test stands in for a file system without one.
    typealias ExclusiveRename = (OpenItem, String, DirectoryHandle) -> Result<Void, POSIXError>

    /// A file system that cannot refuse to replace by itself answers `ENOTSUP` (rename(2)), as exFAT does for a free
    /// name. There the name is first taken with an empty placeholder of the item's kind, which only a free name
    /// allows, and a plain rename then replaces the placeholder. Only the item that was opened moves, never another
    /// renamed into its place.
    static func rename(
        _ item: OpenItem,
        to name: String,
        in directory: DirectoryHandle,
        exclusively: ExclusiveRename
    ) -> Result<Void, POSIXError> {
        var info = stat()
        guard item.name.withCString({ fstatat(item.parent.descriptor, $0, &info, AT_SYMLINK_NOFOLLOW) }) == 0 else {
            return .failure(.last)
        }
        guard let identity = item.identity, ItemIdentity(info) == identity else { return .failure(POSIXError(.ENOENT)) }
        switch exclusively(item, name, directory) {
        case .failure(let error) where error.code == .ENOTSUP:
            return renameOntoPlaceholder(item, to: name, in: directory)
        case let result:
            return result
        }
    }

    private static func renameOntoPlaceholder(
        _ item: OpenItem,
        to name: String,
        in directory: DirectoryHandle
    ) -> Result<Void, POSIXError> {
        var info = stat()
        guard item.name.withCString({ fstatat(item.parent.descriptor, $0, &info, AT_SYMLINK_NOFOLLOW) }) == 0 else {
            return .failure(.last)
        }
        let isFolder = info.st_mode & S_IFMT == S_IFDIR
        let placeholder: ItemIdentity
        switch makePlaceholder(named: name, in: directory, isFolder: isFolder) {
        case .success(let made): placeholder = made
        case .failure(let error): return .failure(error)
        }
        let moved = item.name.withCString { from in
            name.withCString { to in renameat(item.parent.descriptor, from, directory.descriptor, to) }
        }
        guard moved == 0 else {
            let error = POSIXError.last
            removePlaceholder(placeholder, named: name, in: directory, isFolder: isFolder)
            return .failure(error)
        }
        return .success(())
    }

    /// Makes an empty folder, or an empty file for anything else, at `name`, failing with `EEXIST` when it is taken.
    private static func makePlaceholder(
        named name: String,
        in directory: DirectoryHandle,
        isFolder: Bool
    ) -> Result<ItemIdentity, POSIXError> {
        var info = stat()
        if isFolder {
            guard name.withCString({ mkdirat(directory.descriptor, $0, 0o700) }) == 0 else { return .failure(.last) }
            guard name.withCString({ fstatat(directory.descriptor, $0, &info, AT_SYMLINK_NOFOLLOW) }) == 0 else {
                let error = POSIXError.last
                _ = name.withCString { unlinkat(directory.descriptor, $0, AT_REMOVEDIR) }
                return .failure(error)
            }
        } else {
            let file = name.withCString {
                openat(directory.descriptor, $0, O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW | O_CLOEXEC, 0o600)
            }
            guard file >= 0 else { return .failure(.last) }
            defer { close(file) }
            guard fstat(file, &info) == 0 else { return .failure(.last) }
        }
        return .success(ItemIdentity(info))
    }

    /// Takes away the placeholder a failed rename left, only while it is still the one made for it.
    private static func removePlaceholder(
        _ placeholder: ItemIdentity,
        named name: String,
        in directory: DirectoryHandle,
        isFolder: Bool
    ) {
        var info = stat()
        guard
            name.withCString({ fstatat(directory.descriptor, $0, &info, AT_SYMLINK_NOFOLLOW) }) == 0,
            ItemIdentity(info) == placeholder
        else { return }
        _ = name.withCString { unlinkat(directory.descriptor, $0, isFolder ? AT_REMOVEDIR : 0) }
    }

    private static func renameExclusively(
        _ item: OpenItem,
        to name: String,
        in directory: DirectoryHandle
    ) -> Result<Void, POSIXError> {
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
