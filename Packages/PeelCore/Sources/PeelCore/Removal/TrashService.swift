public import Foundation
internal import PeelPrivileged

public struct TrashedItem: Sendable, Hashable, Codable {
    public let originalURL: URL
    public let trashedURL: URL
    public let date: Date
    /// Which item went to the Trash, read there as it landed, so an item that lands in the same place once the Trash
    /// is emptied is never taken for it. Nil in what was recorded before Peel kept it.
    public let identity: Identity?
    /// The launchd job Peel stopped once this file moved, by its label, which putting the file back starts again.
    public internal(set) var stoppedJob: String?

    /// An item as its volume knows it: its inode and when it was made, which a move within the volume keeps. The
    /// volume's device number is left out, since it follows the order volumes are mounted in.
    public struct Identity: Sendable, Hashable, Codable {
        let inode: UInt64
        let birth: Int64

        init(_ identity: ItemIdentity) {
            inode = identity.inode
            birth = identity.birth
        }

        /// The identity of the item at `url` itself, never of what a link there leads to.
        init?(ofItemAt url: URL) {
            guard let identity = ItemIdentity(ofItemAt: url.path(percentEncoded: false)) else { return nil }
            self.init(identity)
        }
    }

    init(originalURL: URL, trashedURL: URL, date: Date, identity: Identity? = nil, stoppedJob: String? = nil) {
        self.originalURL = originalURL
        self.trashedURL = trashedURL
        self.date = date
        self.identity = identity
        self.stoppedJob = stoppedJob
    }

    /// Where the item stands now, as the disk says.
    public enum Standing: Sendable, Equatable {
        case inTheTrash
        /// Nothing is where it went, or, when Peel knows which item went, another item is.
        case gone
        /// macOS would not let Peel look, so whether it is there is not known.
        case notKnown
    }

    public var standing: Standing {
        var info = stat()
        guard lstat(trashedURL.path(percentEncoded: false), &info) == 0 else {
            return errno == ENOENT || errno == ENOTDIR ? .gone : .notKnown
        }
        guard let identity else { return .inTheTrash }
        return Identity(ItemIdentity(info)) == identity ? .inTheTrash : .gone
    }

    /// Whether the item is still where it went in the Trash: something is there and, when Peel knows which item
    /// went, it is that item.
    public var isInTheTrash: Bool {
        standing == .inTheTrash
    }
}

public struct TrashFailure: Sendable, Hashable {
    public enum Reason: Sendable, Hashable {
        /// `RemovalGuard` refuses it, for that reason. Nil for a refusal recorded before Peel kept the reason.
        case guarded(GuardRefusal?)
        case changedSinceScan
        /// Listed as an orphan, but an app installed since the scan claims it.
        case claimedSinceScan
        case lastCopy
        case notPermitted
        /// It is locked, as Finder's Get Info locks an item, so it cannot move until the lock is taken off.
        case locked
        /// It needs administrator rights, and the helper that has them is not installed or not allowed.
        case needsHelper
        /// It is in the Trash, but macOS did not say where and Peel could not find it, so only Finder can put it back.
        case movedWithoutATrace
        /// What moved by name was not the item the guard checked. It is in the Trash under this name.
        case somethingElseMoved(named: String)
        /// History cannot be read, so nothing moves: what moved could not be listed for Put Back.
        case historyUnreadable
        /// These processes hold a file open in it, and moving it would pull it from under them.
        case heldOpen(by: [String])
        case failed(String)
    }

    public let url: URL
    public let reason: Reason

    public init(url: URL, reason: Reason) {
        self.url = url
        self.reason = reason
    }
}

extension TrashFailure.Reason {
    /// Whether the refusal is about the item, which as it is now would be refused again, rather than about Peel's own
    /// state: History it cannot read, or the helper it needs.
    public var isAboutTheItem: Bool {
        switch self {
        case .historyUnreadable, .needsHelper: false
        case .guarded, .changedSinceScan, .claimedSinceScan, .lastCopy, .notPermitted, .locked, .movedWithoutATrace,
             .somethingElseMoved, .heldOpen, .failed: true
        }
    }

    /// A fixed word for the reason, which the refusal log stores. It does not change with the text on screen, so
    /// an old record still reads.
    public var name: String {
        switch self {
        case .guarded(let refusal): refusal?.name ?? "protected-location"
        case .changedSinceScan: "changed-since-scan"
        case .claimedSinceScan: "claimed-since-scan"
        case .lastCopy: "last-copy"
        case .notPermitted: "not-permitted"
        case .locked: "locked"
        case .needsHelper: "needs-helper"
        case .movedWithoutATrace: "moved-without-a-trace"
        case .somethingElseMoved: "something-else-moved"
        case .historyUnreadable: "history-unreadable"
        case .heldOpen: "held-open"
        case .failed: "failed"
        }
    }

    public var detail: String? {
        switch self {
        case .failed(let message): message
        case .somethingElseMoved(let name): name
        case .heldOpen(let processes): processes.joined(separator: "\n")
        default: nil
        }
    }

    /// The reason a refusal log stored as `name` and `detail`, or nil for a word this version doesn't know.
    public init?(name: String, detail: String?) {
        if let refusal = GuardRefusal(name: name) {
            self = .guarded(refusal)
            return
        }
        switch name {
        case "protected-location": self = .guarded(nil)
        case "changed-since-scan": self = .changedSinceScan
        case "claimed-since-scan": self = .claimedSinceScan
        case "last-copy": self = .lastCopy
        case "not-permitted": self = .notPermitted
        case "locked": self = .locked
        case "needs-helper": self = .needsHelper
        case "moved-without-a-trace": self = .movedWithoutATrace
        case "something-else-moved": self = .somethingElseMoved(named: detail ?? "")
        case "history-unreadable": self = .historyUnreadable
        case "held-open": self = .heldOpen(by: (detail ?? "").split(separator: "\n").map(String.init))
        case "failed": self = .failed(detail ?? "")
        default: return nil
        }
    }
}

public enum RestoreFailure: Sendable, Hashable {
    case missingFromTrash
    case alreadyThere
    case needsHelper
    case notAllowed
    case failed(String)
}

public struct TrashResult: Sendable {
    public var trashed: [TrashedItem] = []
    public var failures: [TrashFailure] = []

    public init(trashed: [TrashedItem] = [], failures: [TrashFailure] = []) {
        self.trashed = trashed
        self.failures = failures
    }

    /// Marks each item whose move stopped the job it declares.
    mutating func note(_ stopped: [LaunchdCleanup.Job]) {
        for job in stopped {
            for index in trashed.indices where trashed[index].originalURL == job.plist {
                trashed[index].stoppedJob = job.label
            }
        }
    }
}

public struct TrashService: Sendable {
    /// Answers the jobs it stopped.
    typealias StopJobs = @Sendable ([LaunchdCleanup.Job], _ canUseHelper: Bool) async -> [LaunchdCleanup.Job]
    typealias StartJob = @Sendable (LaunchdCleanup.Job, _ canUseHelper: Bool) async -> Void
    typealias ForgetDomains = @Sendable ([URL], _ owner: String?) async -> Void
    typealias MoveThroughHelper = @Sendable ([URL]) async -> TrashResult
    typealias PutBackDockTiles = @Sendable (URL) async -> Void

    let environment: SearchEnvironment
    private let removalGuard: RemovalGuard
    private let stopJobs: StopJobs
    private let startJob: StartJob
    private let forgetDomains: ForgetDomains
    private let moveThroughHelper: MoveThroughHelper
    private let putBackDockTiles: PutBackDockTiles
    private let moveToTrash: @Sendable (URL) throws -> URL
    private let ownMoves: OwnTrashMoves
    /// Where each item is written down as soon as it moves, so a removal cut short still reaches History.
    private let journal: RemovalJournal?

    public init(environment: SearchEnvironment = .current, exclusions: Exclusions = .none) {
        let removalGuard = RemovalGuard(environment: environment, exclusions: exclusions)
        self.init(
            environment: environment,
            removalGuard: removalGuard,
            stopJobs: LaunchdCleanup.stop,
            startJob: LaunchdCleanup.start,
            forgetDomains: { await PreferenceCleanup.forgetDomains(for: $0, ownedBy: $1) },
            moveThroughHelper: Self.moveThroughTheHelper,
            putBackDockTiles: { await DockTiles().putBack($0) },
            moveToTrash: { try Self.moveToSystemTrash($0, refusal: removalGuard.refusal(of:)) },
            ownMoves: .shared,
            journal: RemovalJournal(beside: RemovalHistory.defaultURL)
        )
    }

    /// For tests. Unless a test passes its own, it stops and starts no launchd job, forgets no preference domain, acts
    /// as if there were no helper, changes no Dock, and writes no journal.
    init(
        environment: SearchEnvironment,
        exclusions: Exclusions = .none,
        stopJobs: @escaping StopJobs = { _, _ in [] },
        startJob: @escaping StartJob = { _, _ in },
        forgetDomains: @escaping ForgetDomains = { _, _ in },
        moveThroughHelper: @escaping MoveThroughHelper = Self.asIfThereWereNoHelper,
        putBackDockTiles: @escaping PutBackDockTiles = { _ in },
        ownMoves: OwnTrashMoves = OwnTrashMoves(),
        journal: RemovalJournal? = nil,
        moveToTrash: @escaping @Sendable (URL) throws -> URL
    ) {
        self.init(
            environment: environment,
            removalGuard: RemovalGuard(environment: environment, exclusions: exclusions),
            stopJobs: stopJobs,
            startJob: startJob,
            forgetDomains: forgetDomains,
            moveThroughHelper: moveThroughHelper,
            putBackDockTiles: putBackDockTiles,
            moveToTrash: moveToTrash,
            ownMoves: ownMoves,
            journal: journal
        )
    }

    private init(
        environment: SearchEnvironment,
        removalGuard: RemovalGuard,
        stopJobs: @escaping StopJobs,
        startJob: @escaping StartJob,
        forgetDomains: @escaping ForgetDomains,
        moveThroughHelper: @escaping MoveThroughHelper,
        putBackDockTiles: @escaping PutBackDockTiles,
        moveToTrash: @escaping @Sendable (URL) throws -> URL,
        ownMoves: OwnTrashMoves,
        journal: RemovalJournal?
    ) {
        self.environment = environment
        self.removalGuard = removalGuard
        self.stopJobs = stopJobs
        self.startJob = startJob
        self.forgetDomains = forgetDomains
        self.moveThroughHelper = moveThroughHelper
        self.putBackDockTiles = putBackDockTiles
        self.moveToTrash = moveToTrash
        self.ownMoves = ownMoves
        self.journal = journal
    }

    /// False while the saved exclusions are not read yet or cannot be read, when nothing moves.
    public var knowsTheExclusions: Bool { removalGuard.knowsTheExclusions }

    /// Why `url` would not move, or nil when it would. A plan can show this before anything moves, since the move
    /// asks the same guard.
    public func refusal(of url: URL) -> TrashFailure.Reason? {
        if let refusal = removalGuard.refusal(of: url) { return .guarded(refusal) }
        return historyCanBeRead ? nil : .historyUnreadable
    }

    /// Why each of `urls` would not move now, by the checks a move makes before it starts: the guard, History, and the
    /// programs holding it. An item missing from the answer would move.
    func refusalsNow(of urls: [URL], lettingTheirProgramsRun apps: Set<URL>) -> [URL: TrashFailure.Reason] {
        let openFiles = OpenFiles()
        var refusals: [URL: TrashFailure.Reason] = [:]
        for url in urls {
            if let refusal = refusal(of: url) {
                refusals[url] = refusal
            } else if case let holders = openFiles.holders(of: url, lettingItsProgramsRun: apps.contains(url)),
                      !holders.isEmpty {
                refusals[url] = .heldOpen(by: holders)
            }
        }
        return refusals
    }

    /// Whether the History this service's moves are recorded in can be read. Nothing moves while it cannot, since
    /// what moved could not be listed for Put Back.
    private var historyCanBeRead: Bool {
        journal?.historyCanBeRead ?? true
    }

    /// Every item of `urls` refused, while History cannot be read. An item the guard refuses keeps that reason,
    /// which outlasts this one.
    private func refusingAllWhileHistoryCannotBeRead(_ urls: [URL]) -> TrashResult? {
        guard !historyCanBeRead else { return nil }
        let refused = urls.map { TrashFailure(url: $0, reason: refusal(of: $0) ?? .historyUnreadable) }
        return TrashResult(failures: refused)
    }

    /// Moves `urls` to the Trash as the current user, then stops the launchd jobs and forgets the preference
    /// domains of what moved. `owner` is the bundle identifier of the app being reset: its own preference domain
    /// is forgotten even when Apple wrote the app.
    @concurrent
    public func trash(_ urls: [URL], ownedBy owner: String? = nil) async -> TrashResult {
        if let refused = refusingAllWhileHistoryCannotBeRead(urls) { return refused }
        return await trash(urls, ownedBy: owner, removal: UUID(), lettingTheirProgramsRun: [])
    }

    /// Moves files Peel made for itself, which History never lists, such as a copy of settings it could not
    /// finish: to the Trash like anything else, with nothing written down for History.
    @concurrent
    func trashOwnFiles(_ urls: [URL]) async -> TrashResult {
        await trash(urls, ownedBy: nil, removal: nil, lettingTheirProgramsRun: [])
    }

    /// Moves `urls` as the current user, as part of `removal`, the move the journal groups them by, or of none.
    private func trash(
        _ urls: [URL],
        ownedBy owner: String?,
        removal: UUID?,
        lettingTheirProgramsRun apps: Set<URL>
    ) async -> TrashResult {
        // The guard reads the disk, so it is asked once for each item.
        let refusals = urls.reduce(into: [URL: GuardRefusal]()) { $0[$1] = removalGuard.refusal(of: $1) }
        let allowed = urls.filter { refusals[$0] == nil }
        let openFiles = OpenFiles()
        // Read before the move, while the files are still there to say which jobs they declare.
        let jobs = LaunchdCleanup.jobs(for: allowed, environment: environment)

        var result = TrashResult()
        var moved = Folders()
        ownMoves.began()
        for url in urls {
            if let refusal = refusals[url] {
                result.failures.append(TrashFailure(url: url, reason: .guarded(refusal)))
                continue
            }
            // An item inside a folder that just moved went with it: it is neither moved again nor a failure.
            let path = PathPattern.comparablePath(of: url)
            guard !moved.hold(path) else { continue }
            let holders = openFiles.holders(of: url, lettingItsProgramsRun: apps.contains(url))
            guard holders.isEmpty else {
                result.failures.append(TrashFailure(url: url, reason: .heldOpen(by: holders)))
                continue
            }
            do {
                let trashedURL = try moveToTrash(url)
                let item = TrashedItem(
                    originalURL: url,
                    trashedURL: trashedURL,
                    date: .now,
                    identity: .init(ofItemAt: trashedURL)
                )
                if let removal {
                    journal?.note([item], batch: removal)
                }
                result.trashed.append(item)
                moved.add(path)
                MoveCount.current?.add(1)
            } catch {
                let reason = Self.reason(for: error)
                let isLocked = reason == .notPermitted && FileAccess.isLockedInFinder(url)
                result.failures.append(TrashFailure(url: url, reason: isLocked ? .locked : reason))
            }
        }
        ownMoves.ended(landedAt: result.trashed.map(\.trashedURL))
        result.note(await finish(result, stopping: jobs, canUseHelper: false, owner: owner))
        return result
    }

    /// Moves `privilegedURLs` through the privileged helper and everything else as the current user.
    @concurrent
    public func trash(_ urls: [URL], usingHelperFor privilegedURLs: Set<URL>) async -> TrashResult {
        await trash(urls, usingHelperFor: privilegedURLs, removal: UUID(), lettingTheirProgramsRun: [])
    }

    /// Moves `apps` first, then what `files` returns for the apps that stayed, as one removal. An app's files wait
    /// for it, so an app that stays keeps everything of its own. A program running from inside one of
    /// `lettingTheirProgramsRun` doesn't keep it, since that app uninstalls itself once it has moved.
    @concurrent
    public func trash(
        apps: [URL],
        thenFiles files: @Sendable (_ appsThatStayed: Set<URL>) -> [URL],
        usingHelperFor privilegedURLs: Set<URL>,
        lettingTheirProgramsRun running: Set<URL>
    ) async -> TrashResult {
        let removal = UUID()
        var result = apps.isEmpty
            ? TrashResult()
            : await trash(apps, usingHelperFor: privilegedURLs, removal: removal, lettingTheirProgramsRun: running)
        let moved = Set(result.trashed.map(\.originalURL))
        let rest = files(Set(apps.filter { !moved.contains($0) }))
        guard !rest.isEmpty else { return result }
        let more = await trash(rest, usingHelperFor: privilegedURLs, removal: removal, lettingTheirProgramsRun: [])
        result.trashed += more.trashed
        result.failures += more.failures
        return result
    }

    private func trash(
        _ urls: [URL],
        usingHelperFor privilegedURLs: Set<URL>,
        removal: UUID,
        lettingTheirProgramsRun apps: Set<URL>
    ) async -> TrashResult {
        if let refused = refusingAllWhileHistoryCannotBeRead(urls) { return refused }
        var result = await trash(
            urls.filter { !privilegedURLs.contains($0) },
            ownedBy: nil,
            removal: removal,
            lettingTheirProgramsRun: apps
        )
        let helperURLs = urls.filter(privilegedURLs.contains)
        guard !helperURLs.isEmpty else { return result }

        var permitted: [URL] = []
        for url in helperURLs {
            if let refusal = removalGuard.refusal(of: url) {
                result.failures.append(TrashFailure(url: url, reason: .guarded(refusal)))
            } else {
                permitted.append(url)
            }
        }
        // An item inside another folder of this request goes with that folder. Sent on its own, the helper would
        // find it gone and report a failure.
        var paths = Folders()
        permitted.forEach { paths.add(PathPattern.comparablePath(of: $0)) }
        let openFiles = OpenFiles()
        var allowed: [URL] = []
        for url in permitted {
            guard !paths.hold(PathPattern.comparablePath(of: url)) else { continue }
            let holders = openFiles.holders(of: url, lettingItsProgramsRun: apps.contains(url))
            guard holders.isEmpty else {
                result.failures.append(TrashFailure(url: url, reason: .heldOpen(by: holders)))
                continue
            }
            allowed.append(url)
        }
        let jobs = LaunchdCleanup.jobs(for: allowed, environment: environment)
        // A command-line tool's link leads into its app until the app has moved, and the helper takes such a link
        // only once it leads nowhere, so the links go after everything else.
        let reach = HelperReach(environment: environment)
        let links = Set(allowed.filter(reach.takesOnlyALink))
        ownMoves.began()
        var helperResult = TrashResult()
        for batch in [allowed.filter { !links.contains($0) }, allowed.filter(links.contains)] where !batch.isEmpty {
            let moved = await moveThroughHelper(batch)
            journal?.note(moved.trashed, batch: removal)
            MoveCount.current?.add(moved.trashed.count)
            helperResult.trashed += moved.trashed
            helperResult.failures += moved.failures
        }
        ownMoves.ended(landedAt: helperResult.trashed.map(\.trashedURL))
        result.trashed += helperResult.trashed
        result.failures += helperResult.failures
        result.note(await finish(helperResult, stopping: jobs, canUseHelper: true, owner: nil))
        return result
    }

    /// Stops the jobs and forgets the preference domains of what really moved, and answers the jobs it stopped. It
    /// runs after the move: a job stopped before a move that fails would stay stopped with its file in place, and
    /// cfprefsd would forget settings that are still on disk.
    private func finish(
        _ result: TrashResult,
        stopping jobs: [LaunchdCleanup.Job],
        canUseHelper: Bool,
        owner: String?
    ) async -> [LaunchdCleanup.Job] {
        let moved = result.trashed.map(\.originalURL)
        let stopped = await stopJobs(jobs.filter { moved.contains($0.plist) }, canUseHelper)
        await forgetDomains(moved, owner)
        return stopped
    }

    /// Moves `urls` through the helper. When the helper is not enabled, nothing moves and every item fails with
    /// `.needsHelper`.
    private static func moveThroughTheHelper(_ urls: [URL]) async -> TrashResult {
        guard PrivilegedHelper.status == .enabled else { return await asIfThereWereNoHelper(urls) }
        return await PrivilegedHelper.moveToTrash(urls)
    }

    private static func asIfThereWereNoHelper(_ urls: [URL]) async -> TrashResult {
        TrashResult(failures: urls.map { TrashFailure(url: $0, reason: .needsHelper) })
    }

    /// Moves an item from the Trash back where it came from, through the helper when the folder needs
    /// administrator rights, and puts back the Dock tiles an uninstall took out for it.
    @concurrent
    public func restore(_ item: TrashedItem, canUseHelper: Bool = false) async -> RestoreFailure? {
        let failure = await moveBack(item, canUseHelper: canUseHelper)
        if failure == nil {
            await putBackDockTiles(item.originalURL)
            // The label comes from History, which any process of the user can rewrite, so the job starts only as the
            // file now back in place declares it.
            if let label = item.stoppedJob,
               let job = LaunchdCleanup.jobs(for: [item.originalURL], environment: environment).first,
               job.label == label {
                await startJob(job, canUseHelper)
            }
        }
        return failure
    }

    private func moveBack(_ item: TrashedItem, canUseHelper: Bool) async -> RestoreFailure? {
        // The record comes from a file any process of the user can rewrite, so it is a request, not a fact.
        // Putting an item back must not write where removal is refused, or move a file that is not in a Trash.
        guard removalGuard.allowsPuttingBack(item.trashedURL, at: item.originalURL), isInATrash(item.trashedURL) else {
            return .notAllowed
        }

        let fileManager = FileManager.default
        guard item.isInTheTrash else { return .missingFromTrash }
        guard !item.originalURL.isThere else { return .alreadyThere }

        let parent = item.originalURL.deletingLastPathComponent()
        // Missing folders are created again, so write access is checked on the nearest folder that exists.
        var ancestor = parent.path(percentEncoded: false)
        while !fileManager.fileExists(atPath: ancestor), ancestor != "/" {
            ancestor = (ancestor as NSString).deletingLastPathComponent
        }
        if fileManager.isWritableFile(atPath: ancestor) {
            do {
                try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
                try Self.putBack(item) { removalGuard.refusal(ofPuttingBack: item.trashedURL, at: $0) }
                return nil
            } catch is RefusedOnceHeld {
                return .notAllowed
            } catch is NotTheItemThatMoved {
                return .missingFromTrash
            } catch POSIXError.EEXIST {
                return .alreadyThere
            } catch {
                guard Self.reason(for: error) == .notPermitted else { return .failed(error.localizedDescription) }
            }
        }
        guard canUseHelper, PrivilegedHelper.status == .enabled else { return .needsHelper }
        guard let failure = await PrivilegedHelper.restore(item) else { return nil }
        return .failed(failure)
    }

    /// Moves `item` back from the Trash through a descriptor for its folder, which must already exist. The guard
    /// is asked again about the destination as the kernel names it, and the move never replaces an item there.
    static func putBack(_ item: TrashedItem, refusal: (URL) -> GuardRefusal?) throws {
        let trashed = try OpenItem.at(item.trashedURL.path(percentEncoded: false)).get()
        if let identity = item.identity, trashed.identity.map(TrashedItem.Identity.init) != identity {
            throw NotTheItemThatMoved()
        }
        let folder = try DirectoryHandle.at(item.originalURL.deletingLastPathComponent().path(percentEncoded: false))
            .get()
        guard let held = folder.currentPath else { throw POSIXError(.ENOENT) }
        let name = item.originalURL.lastPathComponent
        let destination = URL(filePath: held, directoryHint: .isDirectory).appending(path: name)
        if let refused = refusal(destination) { throw RefusedOnceHeld(refusal: refused) }
        try TrashMover.rename(trashed, to: name, in: folder).get()
    }

    /// Whether `url` sits directly in a Trash: `~/.Trash`, or `.Trashes/<uid>` at the root of its volume. The
    /// folder is compared with links resolved, since one that is only called `.Trash` can be a link into
    /// Messages. `FileManager` is not asked: for a folder in iCloud Drive it names iCloud's Trash, not Peel's.
    public func isInATrash(_ url: URL) -> Bool {
        guard let folder = resolvedFolder(of: url) else { return false }
        return trashes(forItemsIn: folder).contains(folder)
    }

    /// Whether `url` is in a Trash, directly or in a folder there, where nothing can be moved again.
    public func isInsideATrash(_ url: URL) -> Bool {
        guard let folder = resolvedFolder(of: url) else { return false }
        return trashes(forItemsIn: folder).contains { PathComponents.isPath(folder, atOrInside: $0) }
    }

    private func resolvedFolder(of url: URL) -> String? {
        guard !url.pathComponents.contains(where: { $0 == "." || $0 == ".." }) else { return nil }
        return PrivilegedPathPolicy.resolvedPath(url.deletingLastPathComponent().path(percentEncoded: false))
    }

    /// The Trashes an item in `folder` could be in, with links resolved: the home's, and its volume's.
    private func trashes(forItemsIn folder: String) -> [String] {
        var trashes = [URL.homeDirectory, environment.homeDirectory].map {
            $0.appending(path: ".Trash", directoryHint: .isDirectory)
        }
        if let volume = try? URL(filePath: folder).resourceValues(forKeys: [.volumeURLKey]).volume {
            trashes.append(volume.appending(path: ".Trashes/\(getuid())", directoryHint: .isDirectory))
        }
        return trashes.compactMap { PrivilegedPathPolicy.resolvedPath($0.path(percentEncoded: false)) }
    }

    /// The failure reason for an error a move threw. macOS does not say which permission is missing, so any
    /// refusal is `.notPermitted`, and the caller decides what it means.
    static func reason(for error: any Error) -> TrashFailure.Reason {
        if let refused = error as? RefusedOnceHeld { return .guarded(refused.refusal) }
        if error is MovedWithoutATrace { return .movedWithoutATrace }
        if let moved = error as? SomethingElseMoved {
            return .somethingElseMoved(named: moved.trashedURL.lastPathComponent)
        }
        let error = error as NSError
        if error.domain == NSCocoaErrorDomain,
           [NSFileWriteNoPermissionError, NSFileReadNoPermissionError].contains(error.code) {
            return .notPermitted
        }
        let codes = ([error] + error.underlyingErrors.map { $0 as NSError }).filter { $0.domain == NSPOSIXErrorDomain }
            .map(\.code)
        if codes.contains(Int(EPERM)) || codes.contains(Int(EACCES)) { return .notPermitted }
        return .failed(error.localizedDescription)
    }

    /// The item moved, but macOS did not say where and Peel could not find it.
    struct MovedWithoutATrace: Error {}

    /// The guard refused the item once its folder was held open and named by the kernel.
    struct RefusedOnceHeld: Error {
        let refusal: GuardRefusal
    }

    /// What sits where an item went in the Trash is another item: the Trash was emptied, and something of the same
    /// name landed there since.
    struct NotTheItemThatMoved: Error {}

    /// A move by name put something other than the checked item in the Trash.
    struct SomethingElseMoved: Error {
        let trashedURL: URL
    }

    /// Moves `url` to the Trash, making sure the item that moves is the one the guard allowed. Checked by name and
    /// then moved by name, its folder could be swapped for a link into Messages between the two steps. So the
    /// folder is held open, the guard is asked about the kernel's own path for it, and the move goes through the
    /// descriptor, as the helper's does.
    static func moveToSystemTrash(
        _ url: URL,
        trash: (URL) throws -> URL = Self.trashMacOSNames,
        byName: (URL) throws -> URL = Self.moveByName,
        refusal: (URL) -> GuardRefusal?
    ) throws -> URL {
        let item = try OpenItem.at(url.path(percentEncoded: false)).get()
        guard let folder = item.parent.currentPath else { throw POSIXError(.ENOENT) }
        let held = URL(filePath: folder, directoryHint: .isDirectory).appending(path: item.name)
        if let refused = refusal(held) { throw RefusedOnceHeld(refusal: refused) }

        guard let named = try? trash(held) else {
            // A volume where nothing was ever trashed has no Trash yet, and only `FileManager.trashItem` creates
            // one. That call moves by name, so the item it moved is checked against the one the guard allowed.
            let trashedURL = try byName(held)
            guard ItemIdentity(ofItemAt: trashedURL.path(percentEncoded: false)) == item.identity else {
                throw SomethingElseMoved(trashedURL: trashedURL)
            }
            return trashedURL
        }
        // Another account can make `.Trashes/<uid>` on a shared disk before its owner does, and read what lands there.
        let bin = try DirectoryHandle.at(named.path(percentEncoded: false)).get()
        guard bin.ownerIdentifier() == getuid() else { throw POSIXError(.EACCES) }
        return URL(filePath: try TrashMover.move(item, into: bin).get())
    }

    private static func trashMacOSNames(for url: URL) throws -> URL {
        try FileManager.default.url(for: .trashDirectory, in: .userDomainMask, appropriateFor: url, create: true)
    }

    private static func moveByName(_ url: URL) throws -> URL {
        // Taken before the move, in case macOS does not say where the item went.
        let link = FileIdentity.Link.of(url)
        var resultingURL: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &resultingURL)
        if let trashedURL = resultingURL as URL? { return trashedURL }
        // The item has already moved, and History needs to know where to. The folder it left is still there
        // to say which volume's Trash took it; the item itself is not.
        let folder = url.deletingLastPathComponent()
        guard
            let link,
            let trash = try? FileManager.default.url(
                for: .trashDirectory,
                in: .userDomainMask,
                appropriateFor: folder,
                create: false
            ),
            let trashedURL = item(link, in: trash)
        else { throw MovedWithoutATrace() }
        return trashedURL
    }

    /// The item in `trash` with the device and inode in `link`. A move within a volume keeps the inode, while the
    /// name proves nothing: macOS renames an item whose name is taken, so an older item of the same name could be
    /// found instead.
    static func item(_ link: FileIdentity.Link, in trash: URL) -> URL? {
        let contents = (try? FileManager.default.contentsOfDirectory(at: trash, includingPropertiesForKeys: nil)) ?? []
        return contents.first { FileIdentity.Link.of($0) == link }
    }
}

/// Folders a request takes, looked up by a path's own names, one level at a time, rather than compared one by one
/// with every folder: a request of thousands of items would otherwise compare each with all the others.
private struct Folders {
    private var names: Set<[String]> = []

    mutating func add(_ path: String) {
        names.insert(PathComponents.of(path))
    }

    /// Whether `path` sits inside one of the folders, as `PathComponents.isPath(_:inside:)` asks.
    func hold(_ path: String) -> Bool {
        let parts = PathComponents.of(path)
        return (0..<parts.count).contains { names.contains(Array(parts[..<$0])) }
    }
}
