import Darwin
public import Foundation

public enum TrashMover {
    /// Renames `item` into `trash` through both folders' descriptors and returns its new path, under the first of
    /// `names(for:inode:)` that is free. It never copies across volumes and never resolves a path a second time.
    public static func move(_ item: OpenItem, into trash: DirectoryHandle) -> Result<String, POSIXError> {
        move(item, into: trash, exclusively: renameExclusively)
    }

    static func move(
        _ item: OpenItem,
        into trash: DirectoryHandle,
        exclusively: ExclusiveRename
    ) -> Result<String, POSIXError> {
        for candidate in names(for: item.name, inode: item.identity?.inode) {
            switch rename(item, to: candidate, in: trash, exclusively: exclusively) {
            case .success:
                return .success((trash.path as NSString).appendingPathComponent(candidate))
            case .failure(let error):
                guard error.code == .EEXIST else { return .failure(error) }
            }
        }
        return .failure(POSIXError(.EEXIST))
    }

    /// The names a move tries for `name`, in turn: its own, "name 2" to "name 10" as Finder names a copy, then the
    /// name with `inode`, the item's own number, which no other item on its disk has while it exists. So whoever looks
    /// for the item knowing its inode can name every place it may be.
    public static func names(for name: String, inode: UInt64?) -> [String] {
        (1...10).map { Self.name(name, attempt: $0) } + (inode.map { [Self.name(name, adding: " \($0)")] } ?? [])
    }

    /// The name `move` tries at `attempt`: the item's own, then "name 2", "name 3", and so on, as Finder names a copy.
    public static func name(_ name: String, attempt: Int) -> String {
        attempt > 1 ? Self.name(name, adding: " \(attempt)") : name
    }

    /// `name` with `suffix` before its extension, its own part cut on whole characters so that all of it fits in a
    /// name's 255 bytes.
    static func name(_ name: String, adding suffix: String) -> String {
        var base = (name as NSString).deletingPathExtension
        let pathExtension = (name as NSString).pathExtension
        let rest = pathExtension.isEmpty ? suffix : "\(suffix).\(pathExtension)"
        while !base.isEmpty, (base + rest).utf8.count > Int(NAME_MAX) { base.removeLast() }
        return base + rest
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
        switch presence(of: item) {
        case .there: break
        case .another: return .failure(POSIXError(.ENOENT))
        case .gone(let error): return .failure(error)
        }
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

    private enum Presence {
        case there(ItemIdentity)
        case another
        case gone(POSIXError)
    }

    private static func presence(of item: OpenItem) -> Presence {
        var info = stat()
        guard item.name.withCString({ fstatat(item.parent.descriptor, $0, &info, AT_SYMLINK_NOFOLLOW) }) == 0 else {
            return .gone(.last)
        }
        guard let identity = item.identity, ItemIdentity(info) == identity else { return .another }
        return .there(identity)
    }

    static func renameExclusively(
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
    /// failed, or nil when `ledger` could not record them or keep its staging folder (then nothing moves). Every item
    /// is recorded before any moves, and only the items that stayed are forgotten again. One request can name an item
    /// twice (the same path, or `/var/...` and `/private/var/...`): it moves once and answers for both paths, since
    /// the second try would fail and forgetting it would also forget the record of the item that moved.
    public static func moveRecorded(
        _ items: [(path: String, item: OpenItem)],
        into trash: DirectoryHandle,
        ledger: HelperLedger,
        movedBy user: uid_t
    ) -> (moved: [String: String], failed: [String: String])? {
        moveRecorded(items, into: trash, ledger: ledger, movedBy: user, exclusively: renameExclusively)
    }

    static func moveRecorded(
        _ items: [(path: String, item: OpenItem)],
        into trash: DirectoryHandle,
        ledger: HelperLedger,
        movedBy user: uid_t,
        exclusively: ExclusiveRename
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
        let staged: Void? = ledger.whileStaging { staging in
            for (path, item) in unique {
                let names = Self.names(for: item.name, inode: item.identity?.inode)
                switch move(item, to: names, in: trash, through: staging, for: user, exclusively: exclusively) {
                case .success(let name):
                    moved[path] = (trash.path as NSString).appendingPathComponent(name)
                case .failure(.leftInStaging):
                    // It keeps its record, for the Trash it goes to when the helper starts again.
                    failed[path] = StagedFailure.leftInStaging.explanation
                case .failure(let failure):
                    failed[path] = failure.explanation
                    stayed.append(item)
                }
            }
        }
        guard staged != nil else {
            ledger.forget(unique.map(\.item))
            return nil
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

extension TrashMover {
    enum StagedFailure: Error {
        case failed(POSIXError)
        case refused(PrivilegedPathPolicy.Rejection)
        case notTheItem
        /// The item could neither reach its place nor go back, so it waits in `Staging` for the helper's next start.
        case leftInStaging

        var explanation: String {
            switch self {
            case .failed(let error): error.localizedDescription
            case .refused(let rejection): rejection.explanation
            case .notTheItem: PrivilegedPathPolicy.Rejection.missing.explanation
            case .leftInStaging: HelperRefusal.keptByTheHelper.rawValue
            }
        }
    }

    /// Moves `item` to the first of `names` free in `destination` by way of `staging`, which only the helper can
    /// reach. A rename goes by name, so what arrives is checked there, where nothing can take its place: anything but
    /// the item, or anything `refusing` refuses, goes back.
    static func move(
        _ item: OpenItem,
        to names: some Sequence<String>,
        in destination: DirectoryHandle,
        through staging: DirectoryHandle,
        for user: uid_t,
        refusing: (stat) -> PrivilegedPathPolicy.Rejection? = { _ in nil },
        exclusively: ExclusiveRename = renameExclusively
    ) -> Result<String, StagedFailure> {
        let identity: ItemIdentity
        switch presence(of: item) {
        case .there(let opened): identity = opened
        case .another: return .failure(.notTheItem)
        case .gone(let error): return .failure(.failed(error))
        }
        var staged = "\(user).\(UUID().uuidString).\(item.name)"
        while staged.utf8.count > Int(NAME_MAX) { staged.removeLast() }
        if case .failure(let error) = exclusively(item, staged, staging) { return .failure(.failed(error)) }

        let arrived = staging.status(of: staged).flatMap { ItemIdentity($0) == identity ? $0 : nil }
        let failure: StagedFailure
        if let arrived {
            if let rejection = refusing(arrived) {
                failure = .refused(rejection)
            } else {
                switch place(staged, from: staging, in: destination, as: names) {
                case .success(let name): return .success(name)
                case .failure(let error): failure = .failed(error)
                }
            }
        } else {
            failure = .notTheItem
        }
        let back = place(staged, from: staging, in: item.parent, as: Self.names(for: item.name, inode: identity.inode))
        // The item itself, when it can't go back either, stays here until the helper starts again and moves it to its
        // account's Trash (`HelperLedger.recoverStaged`).
        if case .failure = back, arrived != nil { return .failure(.leftInStaging) }
        return .failure(failure)
    }

    /// Renames `name`, in a folder only root can change, to the first of `names` free in `destination`.
    static func place(
        _ name: String,
        from folder: DirectoryHandle,
        in destination: DirectoryHandle,
        as names: some Sequence<String>
    ) -> Result<String, POSIXError> {
        let item = OpenItem(path: folder.path + "/" + name, name: name, parent: folder)
        for candidate in names {
            switch renameExclusively(item, to: candidate, in: destination) {
            case .success: return .success(candidate)
            case .failure(let error) where error.code == .EEXIST: continue
            case .failure(let error): return .failure(error)
            }
        }
        return .failure(POSIXError(.EEXIST))
    }
}
