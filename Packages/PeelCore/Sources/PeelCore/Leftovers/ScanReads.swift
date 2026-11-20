import Foundation
internal import PeelPrivileged
import Synchronization

/// What the scans of one preparation read of the disk, read once: apps chosen together look through the same
/// locations, and only whose each entry is differs from one app to the next.
final class ScanReads: Sendable {
    enum Listing: Sendable, Equatable {
        /// The names in the folder, sorted: Apple documents the order of a listing as undefined, and where a search
        /// stops at a limit, the order decides what it reaches.
        case names([String])
        case missing
        case unreadable
        /// More entries than a scan reads, with their number when the file system tells it.
        case holdsTooMany(Int?)
    }

    /// The most entries a scan reads of one folder.
    static let entryLimit = 20_000

    typealias List = @Sendable (URL) -> Listing

    private struct Asked: Hashable {
        let path: String
        let home: String
    }

    /// A question answered, or being read with whoever asked the same meanwhile waiting for it.
    private enum Entry<Value: Sendable>: Sendable {
        case known(Value)
        case reading([CheckedContinuation<Value, Never>])
    }

    private let list: List
    private let guardRefuses: LeftoverScanner.Refuses
    private let listings = Mutex<[String: Entry<Listing>]>([:])
    private let refusals = Mutex<[Asked: Entry<Bool>]>([:])
    private let folders = Mutex<[String: Entry<Bool>]>([:])
    private let parents = Mutex<[String: Entry<ParentAccess>]>([:])

    init(
        list: @escaping List = ScanReads.listing(of:),
        refuses: @escaping LeftoverScanner.Refuses = { ProtectedData.refuses($0, home: $1) }
    ) {
        self.list = list
        guardRefuses = refuses
    }

    func listing(of folder: URL) async -> Listing {
        await remembered(in: listings, for: Self.key(of: folder)) { list(folder) }
    }

    func refuses(_ path: String, home: String) async -> Bool {
        await remembered(in: refusals, for: Asked(path: path, home: home)) { guardRefuses(path, home) }
    }

    func isRealFolder(_ url: URL) async -> Bool {
        await remembered(in: folders, for: Self.key(of: url)) { url.isRealFolder }
    }

    func parentAccess(_ folder: URL) async -> ParentAccess {
        await remembered(in: parents, for: Self.key(of: folder)) { ParentAccess(folder) }
    }

    static func listing(of folder: URL) -> Listing {
        listing(of: folder, limit: entryLimit)
    }

    /// Never more of a folder than `limit` entries: the file system is asked how many it holds first. Where it doesn't
    /// tell, the names are read a few at a time, so Stop ends a read under way and a slow one ends at `budget`.
    static func listing(of folder: URL, limit: Int, budget: TimeInterval = FileSize.budget) -> Listing {
        // The enumerator follows no link at the top, as listing a folder by its path does.
        let folder = folder.resolvingSymlinksInPath()
        let path = folder.path(percentEncoded: false)
        if let count = FolderEntries.count(at: path) {
            guard count <= limit else { return .holdsTooMany(count) }
            do {
                return .names(try FileManager.default.contentsOfDirectory(atPath: path).sorted())
            } catch CocoaError.fileReadNoSuchFile {
                return .missing
            } catch {
                return .unreadable
            }
        }
        var failure: (any Error)?
        // It hides what `contentsOfDirectory` hides, such as the `._` files of a disk without extended attributes.
        let entries = FileManager.default.enumerator(
            at: folder, includingPropertiesForKeys: [], options: [.skipsSubdirectoryDescendants]
        ) { _, error in
            failure = error
            return false
        }
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(budget)
        var names: [String] = []
        while let entry = entries?.nextObject() as? URL {
            guard names.count < limit else { return .holdsTooMany(nil) }
            names.append(entry.lastPathComponent)
            if names.count.isMultiple(of: 1_000) {
                if Task.isCancelled { return .unreadable }
                if clock.now > deadline { return .holdsTooMany(nil) }
            }
        }
        guard failure != nil else { return .names(names.sorted()) }
        // What isn't there, a path through a file among it, is missing; what is there and can't be listed isn't.
        var info = stat()
        return stat(path, &info) == 0 ? .unreadable : .missing
    }

    /// What a question finds: its answer, nobody reading it yet, or a read under way.
    private enum Turn<Value: Sendable> {
        case answered(Value)
        case read
        case wait
    }

    /// The first to ask reads, outside the lock, so a slow read holds no other question. Whoever asks the same while
    /// it reads waits for that answer, without holding a thread.
    private func remembered<Key: Hashable & Sendable, Value: Sendable>(
        in memory: borrowing Mutex<[Key: Entry<Value>]>, for key: Key, reading: () -> Value
    ) async -> Value {
        let turn: Turn<Value> = memory.withLock { entries in
            switch entries[key] {
            case .known(let value): return .answered(value)
            case .reading: return .wait
            case nil:
                entries[key] = .reading([])
                return .read
            }
        }
        switch turn {
        case .answered(let value):
            return value
        case .read:
            let value = reading()
            let waiting = memory.withLock { entries in
                defer { entries[key] = .known(value) }
                guard case .reading(let waiting) = entries[key] else { return [CheckedContinuation<Value, Never>]() }
                return waiting
            }
            for waiter in waiting { waiter.resume(returning: value) }
            return value
        case .wait:
            return await withCheckedContinuation { continuation in
                let joined: Turn<Value> = memory.withLock { entries in
                    switch entries[key] {
                    case .known(let value): return .answered(value)
                    case .reading(let waiting):
                        entries[key] = .reading(waiting + [continuation])
                        return .wait
                    case nil: return .read
                    }
                }
                switch joined {
                case .answered(let value): continuation.resume(returning: value)
                case .read: continuation.resume(returning: reading())
                case .wait: break
                }
            }
        }
    }

    private static func key(of url: URL) -> String {
        var path = url.path(percentEncoded: false)
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        return path
    }
}
