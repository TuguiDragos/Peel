import Darwin
public import Foundation
import Synchronization

/// What one walk of a folder found.
public struct FolderContents: Sendable, Hashable {
    public let size: Int64
    /// True when a version control repository was seen inside (`repositoryMarkers`). Work that is not
    /// committed, or not pushed, exists nowhere else.
    public let holdsRepository: Bool
    /// True when a cryptocurrency wallet or a signing key was seen inside (`isWallet(_:)`). Without the file
    /// or a written recovery phrase, the money or the key is gone for good.
    public let holdsWallet: Bool
    /// The latest modification date of anything inside. A folder's own date does not change when a file in
    /// it is rewritten in place.
    public let newestChange: Date?
    /// True when the folder, or a folder inside it, could not be opened, so not everything inside was seen. `size`
    /// then counts only what was, which must never be read as the folder's size. From macOS 27, another team's
    /// container is refused outright.
    public let couldNotBeRead: Bool

    init(size: Int64, holdsRepository: Bool, holdsWallet: Bool = false, newestChange: Date? = nil, couldNotBeRead: Bool = false) {
        self.size = size
        self.holdsRepository = holdsRepository
        self.holdsWallet = holdsWallet
        self.newestChange = newestChange
        self.couldNotBeRead = couldNotBeRead
    }
}

public enum FileSize {
    /// How long Peel waits for one folder before its size counts as unknown. Long enough to measure a very
    /// large folder. A folder that never answers costs this wait once and is not asked again.
    public static let budget: TimeInterval = 8

    /// How a scanner asks for a size. Tests hand in their own, to stand in for a folder that does not answer.
    typealias Measure = @Sendable (URL) async -> Int64?

    static let measure: Measure = { await allocatedSize(of: $0) }

    /// The space a file, or everything inside a folder, takes on disk. Nil for a folder that does not answer
    /// within `budget` or that macOS will not let Peel open. No variant answers zero instead: unknown is not
    /// empty, and every caller has to decide how to handle it.
    @concurrent
    public static func allocatedSize(of url: URL, within budget: TimeInterval = FileSize.budget) async -> Int64? {
        guard let contents = await contents(of: url, within: budget), !contents.couldNotBeRead else { return nil }
        return contents.size
    }

    /// The walk behind `allocatedSize(of:within:)`, which also reports what it saw on the way. Nil when the
    /// folder does not answer within `budget`, or when the task is canceled.
    ///
    /// A folder a file provider owns (a cloud drive, or a container such as Podcasts') can hold a directory
    /// read in the kernel for minutes, and a system call in the kernel cannot be canceled. The I/O policies
    /// `IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES` and `IOPOL_TYPE_VFS_TRIGGER_RESOLVE` do not prevent it. So
    /// the walk runs on a thread of its own, and the caller stops waiting when `budget` runs out.
    ///
    /// Awaited, never blocked on: scanners ask for dozens of sizes at once, and blocking a thread of Swift's
    /// pool (one per core) for each would hold up every other scan. `@concurrent` because even a single file
    /// costs a trip to the disk, which is never made on the caller's actor.
    @concurrent
    public static func contents(of url: URL, within budget: TimeInterval = FileSize.budget) async -> FolderContents? {
        guard let folder = folderToWalk(url) else { return immediateContents(of: url) }
        // A canceled task starts no walk.
        guard !Task.isCancelled else { return nil }
        let answer: Answer
        switch Walks.ask(about: folder) {
        case .answered(let contents):
            return contents
        case .wait(let shared, let isNew):
            answer = shared
            if isNew { start(walking: folder, into: answer, for: Task.currentPriority, countingFor: ScanCount.current) }
        }
        await answer.wait(budget)
        return Walks.leave(folder, answer, isWithdrawn: Task.isCancelled)
    }

    /// Starts the walk on a thread of its own, not a shared pool: a walk that never returns would keep its
    /// pool thread, and enough of them would starve every other walk. The thread runs at the priority of the
    /// task that asked, so a scan the user is watching is not throttled as background work.
    private static func start(walking folder: URL, into answer: Answer, for priority: TaskPriority, countingFor scan: ScanCount?) {
        let thread = Thread {
            let contents = walk(folder, countingFor: scan, unless: { answer.isStopped })
            Walks.finish(folder, with: contents, into: answer)
        }
        thread.qualityOfService = switch priority {
        case .high...: .userInitiated
        case .medium..<(.high): .default
        case .low..<(.medium): .utility
        default: .background
        }
        thread.stackSize = 512 * 1_024
        thread.start()
    }

    /// Nil for anything that is not a folder to walk, which is answered on the spot without a thread.
    private static func folderToWalk(_ url: URL) -> URL? {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return nil }
        return values.isDirectory == true && values.isSymbolicLink != true ? url : nil
    }

    private static func immediateContents(of url: URL) -> FolderContents {
        ScanCount.current?.add(1)
        do {
            let values = try url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .contentModificationDateKey])
            return FolderContents(
                size: Int64(values.totalFileAllocatedSize ?? 0),
                holdsRepository: repositoryMarkers.contains(url.lastPathComponent),
                holdsWallet: isWallet(url.lastPathComponent),
                newestChange: values.contentModificationDate
            )
        } catch CocoaError.fileReadNoSuchFile {
            // Nothing is there, which holds nothing.
            return FolderContents(size: 0, holdsRepository: false)
        } catch {
            // macOS would not say what the item is (a folder around it cannot be searched), so its size is not known.
            return FolderContents(size: 0, holdsRepository: false, couldNotBeRead: true)
        }
    }

    /// True for an item whose contents live only in the cloud (`SF_DATALESS`). Listing such a folder makes its
    /// file provider enumerate it (`NSFileProviderReplicatedExtension.h`), which for an online-only drive means
    /// fetching the whole tree from the server. It holds no local bytes, so the walk skips it.
    static func isDataless(_ url: URL) -> Bool {
        var info = stat()
        guard lstat(url.path(percentEncoded: false), &info) == 0 else { return false }
        return info.st_flags & UInt32(SF_DATALESS) != 0
    }

    /// Walks everything under `url`. Nil when `isStopped` turns true on the way, since half a walk is no answer.
    static func walk(_ url: URL, countingFor scan: ScanCount? = nil, unless isStopped: () -> Bool) -> FolderContents? {
        let fileKeys: Set<URLResourceKey> = [
            .isRegularFileKey, .totalFileAllocatedSizeKey, .linkCountKey, .fileIdentifierKey, .contentModificationDateKey,
        ]
        // Notes whether the folder, or a folder inside it, failed to open. The enumerator reports that only to the
        // error handler and goes on without it, which would read as a folder holding less than it does. A folder
        // that is no longer there holds nothing, which leaves nothing unseen.
        let refused = Refused()
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: Array(fileKeys),
            options: [],
            errorHandler: { _, error in
                if (error as? CocoaError)?.code != .fileReadNoSuchFile { refused.note() }
                return true
            }
        ) else { return FolderContents(size: 0, holdsRepository: false, couldNotBeRead: true) }

        var total: Int64 = 0
        // The folder's own name counts as its entries' do: a `keystore` or a `.git` measured on its own.
        var holdsRepository = repositoryMarkers.contains(url.lastPathComponent)
        var holdsWallet = isWallet(url.lastPathComponent)
        var newestChange: Date?
        // A file with several hard links takes its space once. Counting it once per name would overstate what
        // emptying the folder frees.
        var counted: Set<UInt64> = []
        // Each entry gets its own autorelease pool, or what reading every name leaves behind would pile up in
        // memory until the walk ends.
        walking: while true {
            let step: Step = autoreleasepool {
                guard let file = enumerator.nextObject() as? URL else { return .finished }
                guard !isStopped() else { return .stopped }
                scan?.add(1)
                // Matched by name alone: a Git worktree or submodule has a `.git` file, a plain repository a
                // `.git` folder.
                if repositoryMarkers.contains(file.lastPathComponent) { holdsRepository = true }
                if isWallet(file.lastPathComponent) { holdsWallet = true }
                guard let values = try? file.resourceValues(forKeys: fileKeys) else { return .next }
                if let written = values.contentModificationDate, written > newestChange ?? .distantPast { newestChange = written }
                guard values.isRegularFile == true else {
                    if isDataless(file) { enumerator.skipDescendants() }
                    return .next
                }
                if let links = values.linkCount, links > 1, let identifier = values.fileIdentifier {
                    guard counted.insert(identifier).inserted else { return .next }
                }
                total += Int64(values.totalFileAllocatedSize ?? 0)
                return .next
            }
            switch step {
            case .next: continue
            case .finished: break walking
            case .stopped: return nil
            }
        }
        return FolderContents(
            size: total,
            holdsRepository: holdsRepository,
            holdsWallet: holdsWallet,
            newestChange: newestChange,
            couldNotBeRead: refused.happened
        )
    }

    private enum Step {
        case next, finished, stopped
    }

    /// Whether a folder of the walk refused to open. Set by the enumerator's error handler on the walking thread,
    /// and read once the walk ends.
    private final class Refused: Sendable {
        private let state = Mutex(false)

        var happened: Bool { state.withLock { $0 } }

        func note() {
            state.withLock { $0 = true }
        }
    }

    static let repositoryMarkers: Set<String> = [".git", ".hg", ".svn", ".jj", ".pijul", "_darcs"]

    /// True for the names wallets and their keys go by, as each project's own documentation or source gives them:
    /// `wallet.dat` and names ending in it (Bitcoin, Litecoin and their forks, Zcash's Zingo), a `wallets` or
    /// `wallets2` folder (Electrum, Sparrow, Wasabi, Bitcoin Core, Green), `keystore` and `keystores` (Ethereum,
    /// Foundry, and the key an Android app is signed with), `*.wallet` (Bisq, Exodus, Kaspa), `*.keys` (Monero),
    /// `*.mmdbdoc_v1` (MyMonero), `hsm_secret`, `emergency.recover`, and `channel.backup` (Lightning nodes),
    /// `seed.dat` (phoenixd), `wallet.seed` (Grin), `mnemonics` (Liana), `keyring-file`, `keyring-test`, and
    /// `priv_validator_key.json` (Cosmos), `sui.keystore`, `sqlite_wallets` (Algorand), `encryption-identity.txt`
    /// (Zallet), and `.aptos`.
    static func isWallet(_ name: String) -> Bool {
        let name = name.lowercased()
        return walletNames.contains(name) || walletSuffixes.contains { name.hasSuffix($0) }
    }

    private static let walletNames: Set<String> = [
        "wallets", "wallets2", "keystore", "keystores", "hsm_secret", "emergency.recover", "channel.backup",
        "seed.dat", "wallet.seed", "mnemonics", "keyring-file", "keyring-test", "priv_validator_key.json",
        "sui.keystore", "sqlite_wallets", "encryption-identity.txt", ".aptos",
    ]

    private static let walletSuffixes = ["wallet.dat", ".wallet", ".keys", ".mmdbdoc_v1"]
}

/// What is known about the folders being walked.
///
/// A folder whose walk runs past the budget is marked abandoned and answered with nil from then on, since
/// asking again would only start another thread that may never return. If the walk does finish late, its
/// answer is kept for whoever asks next, so a big folder is unknown only once. A folder being walked is
/// never walked twice: everyone who asks waits for the same answer, so each folder has one thread at most.
private enum Walks {
    enum Entry {
        case walking(Answer)
        case abandoned(Answer)
        case landed(FolderContents)
    }

    enum Asked {
        case answered(FolderContents?)
        case wait(Answer, isNew: Bool)
    }

    private static let entries = Mutex<[String: Entry]>([:])

    /// Returns a known answer, or the walk to wait for (`isNew` when the caller has to start it). An answer
    /// that landed late is handed over once, and the question after that walks the folder again.
    static func ask(about folder: URL) -> Asked {
        entries.withLock { entries in
            let path = PathPattern.comparablePath(of: folder)
            switch entries[path] {
            case .landed(let contents):
                entries[path] = nil
                return .answered(contents)
            case .abandoned:
                return .answered(nil)
            case .walking(let answer):
                answer.join()
                return .wait(answer, isNew: false)
            case nil:
                let answer = Answer()
                answer.join()
                entries[path] = .walking(answer)
                return .wait(answer, isNew: true)
            }
        }
    }

    /// Ends one wait and returns the answer, if there is one. It runs under the same lock as `finish`, so an
    /// answer arriving at the same moment is either returned here or kept, never lost while the folder is
    /// marked abandoned. A canceled wait marks nothing, since it says nothing about the folder, and the walk
    /// is told to stop once nobody is left waiting for it.
    static func leave(_ folder: URL, _ answer: Answer, isWithdrawn: Bool) -> FolderContents? {
        entries.withLock { entries in
            let path = PathPattern.comparablePath(of: folder)
            let isLastToLeave = answer.leave()
            if let found = answer.taken() {
                if case .walking(let current) = entries[path], current === answer { entries[path] = nil }
                return found
            }
            if isWithdrawn {
                if isLastToLeave { answer.stop() }
            } else if case .walking(let current) = entries[path], current === answer {
                entries[path] = .abandoned(answer)
            }
            return nil
        }
    }

    static func finish(_ folder: URL, with contents: FolderContents?, into answer: Answer) {
        entries.withLock { entries in
            let path = PathPattern.comparablePath(of: folder)
            let isCurrent = switch entries[path] {
            case .walking(let current), .abandoned(let current): current === answer
            case .landed, nil: false
            }
            guard let contents else {
                // Stopped partway: the next question walks the folder again.
                if isCurrent { entries[path] = nil }
                return
            }
            answer.give(contents)
            // With nobody left to take it, it is kept for whoever asks next.
            if isCurrent, !answer.isAwaited { entries[path] = .landed(contents) }
        }
    }
}

/// One answer, written by a thread that may never come back and read by everyone who is waiting for it.
private final class Answer: Sendable {
    private struct State {
        var contents: FolderContents?
        var waiters: [Int: CheckedContinuation<Void, Never>] = [:]
        /// Waiters woken before they began to wait, which happens to a task canceled early.
        var woken: Set<Int> = []
        var lastWaiter = 0
        var awaiting = 0
    }

    private let state = Mutex(State())
    private let stopped = Atomic<Bool>(false)

    var isStopped: Bool { stopped.load(ordering: .relaxed) }
    var isAwaited: Bool { state.withLock { $0.awaiting > 0 } }

    func join() {
        state.withLock { $0.awaiting += 1 }
    }

    /// True for the last one out.
    func leave() -> Bool {
        state.withLock { state in
            state.awaiting -= 1
            return state.awaiting <= 0
        }
    }

    func stop() {
        stopped.store(true, ordering: .relaxed)
    }

    func give(_ contents: FolderContents) {
        let waiters = state.withLock { state in
            state.contents = contents
            defer { state.waiters = [:] }
            return Array(state.waiters.values)
        }
        waiters.forEach { $0.resume() }
    }

    func taken() -> FolderContents? {
        state.withLock { $0.contents }
    }

    /// Returns when the answer is given, when `budget` runs out, or when the task is canceled, whichever
    /// comes first. It waits on a continuation, not in a sleep loop: `Task.sleep` throws at once in a canceled
    /// task, so such a loop would spin. The deadline only wakes the waiter, so it is cheap to run at
    /// user-initiated priority, where other work does not hold it back.
    func wait(_ budget: TimeInterval) async {
        guard budget > 0 else { return }
        let waiter = state.withLock { state in
            state.lastWaiter += 1
            return state.lastWaiter
        }
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let goesOnWaiting = state.withLock { state in
                    guard state.contents == nil, !state.woken.contains(waiter) else { return false }
                    state.waiters[waiter] = continuation
                    return true
                }
                guard goesOnWaiting else { return continuation.resume() }
                DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + budget) { self.wake(waiter) }
            }
        } onCancel: {
            wake(waiter)
        }
    }

    /// Each waiter is woken once, by whichever comes first.
    private func wake(_ waiter: Int) {
        let continuation = state.withLock { state in
            state.woken.insert(waiter)
            return state.waiters.removeValue(forKey: waiter)
        }
        continuation?.resume()
    }
}
