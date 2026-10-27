import CoreServices
import Darwin
public import Foundation
import Synchronization
import UniformTypeIdentifiers
internal import PeelPrivileged

public struct FileSearchCriteria: Sendable, Hashable {
    public enum Scope: String, Sendable, Hashable, CaseIterable {
        case home
        case computer
    }

    public var name = ""
    public var kind = FileKind.any
    public var minimumSize: Int64 = 0
    public var unmodifiedDays = 0
    public var scope = Scope.home

    public init() {}

    /// True when a name, a minimum size, or a kind narrows the search. Without one, Spotlight would return every
    /// indexed file. `unmodifiedDays` alone does not count.
    public var isSearchable: Bool {
        !trimmedName.isEmpty || minimumSize > 0 || kind != .any
    }

    public var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// How many of the kind, the size and the age are chosen, each keeping out what a name alone would find.
    public var narrowingFilters: Int {
        [kind != .any, minimumSize > 0, unmodifiedDays > 0].count(where: \.self)
    }

    public func clearingFilters() -> FileSearchCriteria {
        var cleared = self
        cleared.kind = .any
        cleared.minimumSize = 0
        cleared.unmodifiedDays = 0
        return cleared
    }
}

public struct FoundFile: Sendable, Hashable, Identifiable {
    public let url: URL
    /// What moving the file would free (`ReclaimableSpace.of`).
    public let size: Int64
    /// Its length, as Finder shows it and the search's size reads it.
    public let length: Int64
    public let modificationDate: Date
    public let requiresPrivileges: Bool
    /// True when the file sits in a Library folder, so it is an app's working data rather than something the user
    /// made. Such a file is listed last and never selected for the user.
    public var belongsToAnApp = false
    /// The file's identity when it was listed. Results can stay on screen for a long time, and a file written
    /// again under the same name is not the one the row describes.
    public var identity: FileIdentity?

    public var id: URL { url }

    /// True when moving the file frees less than its length: another file shares its storage, or it takes less
    /// space than its length.
    public var freesLessThanItsLength: Bool { size < length }
}

public struct FileSearchResults: Sendable {
    public var files: [FoundFile] = []
    /// True when more than `FileSearch.maximumResults` files were found and the list was cut to that many.
    public var isTruncated = false
    /// The files Spotlight found that the list leaves out, by why. A file the cut left out counts there, not here.
    public var leftOut: [FileSearch.LeftOut: Int] = [:]
    /// False when the query itself could not be made or run, which is not the same as finding nothing.
    public var didRun = true
    /// The disks Spotlight doesn't index, named as Finder names them, asked only when nothing was found.
    public var unindexedDisks: [String] = []
    /// True when Spotlight indexes none of the disks searched.
    public var isNothingIndexed = false
}

public enum FileSearch {
    public static let maximumResults = 2_000

    public enum LeftOut: Sendable, Hashable, CaseIterable {
        /// It syncs to the person's other devices, or lives only in the cloud.
        case syncs
        case excluded
        case exclusionsNotKnown
        /// It is part of macOS, or sits inside something Peel protects.
        case protected
        case couldNotBeRead

        init(_ refusal: GuardRefusal) {
            switch refusal {
            case .inTheCloud: self = .syncs
            case .excluded: self = .excluded
            case .exclusionsNotKnown: self = .exclusionsNotKnown
            case .couldNotLookInside: self = .couldNotBeRead
            case .staysItself, .protectedLocation, .holdsProtectedData, .holdsDocuments, .holdsALibrary,
                 .holdsWorkKeptInACache:
                self = .protected
            }
        }
    }

    enum Judgment: Equatable {
        case listed
        case leftOut(LeftOut)
        /// Not a file of the search's after all, as far as Peel can tell without downloading it.
        case skipped
    }

    /// Runs a Spotlight query and returns the paths it found, or nil when it could not run or was stopped.
    typealias Gather = @concurrent @Sendable (sending MDQuery) async -> [String]?

    /// Moves `files` to the Trash as one removal. A file written again under the same name after it was
    /// listed is a different file, so it fails with `changedSinceScan` instead, checked right before its own move.
    @concurrent
    public static func trash(_ files: [FoundFile], using trashService: TrashService) async -> TrashResult {
        let listed = Dictionary(files.map { ($0.url, $0) }) { first, _ in first }
        return await trashService.trash(files.map(\.url), refusing: { url in
            guard let identity = listed[url]?.identity,
                  FileIdentity.of(url)?.holdsTheSameContents(as: identity) == true
            else { return .changedSinceScan }
            return nil
        })
    }

    /// Returns up to `maximumResults` regular files from the Spotlight index that match `criteria` and that the
    /// removal guard allows. Files in a Library folder come after the rest, and each part is sorted largest first.
    /// Stopping the task stops the query.
    @concurrent
    public static func run(
        _ criteria: FileSearchCriteria,
        environment: SearchEnvironment = .current,
        exclusions: Exclusions = .none
    ) async -> FileSearchResults {
        await run(criteria, environment: environment, exclusions: exclusions) { await SpotlightGathering($0).paths() }
    }

    /// The same, with the query, the disks and their index asked of `gather`, `disks` and `isIndexing`, so a test can
    /// stand in for them.
    static func run(
        _ criteria: FileSearchCriteria,
        environment: SearchEnvironment = .current,
        exclusions: Exclusions = .none,
        gather: Gather,
        disks: (FileSearchCriteria.Scope) -> [SpotlightIndex.Disk]? = { _ in nil },
        isIndexing: @Sendable (URL) async -> Bool? = SpotlightIndex.isIndexing
    ) async -> FileSearchResults {
        guard criteria.isSearchable, let query = makeQuery(for: criteria) else {
            return FileSearchResults(didRun: false)
        }
        let scope = criteria.scope == .home ? kMDQueryScopeHome : kMDQueryScopeComputer
        MDQuerySetSearchScope(query, [scope] as CFArray, 0)
        guard let paths = await gather(query), !Task.isCancelled else { return FileSearchResults(didRun: false) }
        var results = results(from: paths, kind: criteria.kind, environment: environment, exclusions: exclusions)
        guard results.didRun, results.files.isEmpty else { return results }
        let searched = disks(criteria.scope)
            ?? SpotlightIndex.disks(in: criteria.scope, home: environment.homeDirectory)
        for disk in searched where await isIndexing(disk.volume) == false {
            results.unindexedDisks.append(disk.name)
        }
        guard !Task.isCancelled else { return FileSearchResults(didRun: false) }
        results.isNothingIndexed = !searched.isEmpty && results.unindexedDisks.count == searched.count
        return results
    }

    /// Turns the paths Spotlight found into results: checked on disk, sorted, cut to `maximumResults`, and what was
    /// left out counted by why. Separate from the query, so a test can pass its own paths and answers.
    static func results(
        from paths: [String],
        kind: FileKind = .any,
        environment: SearchEnvironment = .current,
        exclusions: Exclusions = .none,
        refusal: ((URL) -> GuardRefusal?)? = nil,
        syncsToOtherDevices: (@Sendable (URL) -> Bool)? = nil
    ) -> FileSearchResults {
        let syncsToOtherDevices = syncsToOtherDevices ?? SyncedFolders().syncsToOtherDevices
        let refusal = refusal ?? RemovalGuard(
            environment: environment, exclusions: exclusions, syncsToOtherDevices: syncsToOtherDevices
        ).refusal(of:)
        let appData = AppDataFolders(home: environment.homeDirectory)
        var results = FileSearchResults()
        var candidates: [(path: String, info: stat, belongsToAnApp: Bool)] = []
        for path in paths {
            guard !Task.isCancelled else { return FileSearchResults(didRun: false) }
            var info = stat()
            guard lstat(path, &info) == 0 else {
                // A file gone since Spotlight saw it isn't left out, but one macOS kept Peel from is.
                if errno == EPERM || errno == EACCES { results.leftOut[.couldNotBeRead, default: 0] += 1 }
                continue
            }
            guard info.st_mode & S_IFMT == S_IFREG else { continue }
            candidates.append((path, info, appData.holds(path)))
        }
        // In the list's order before the guard is asked, so it is asked only about files that can make the list.
        // What an app keeps for itself goes last: the tool is for finding what the user made.
        candidates.sort {
            if $0.belongsToAnApp != $1.belongsToAnApp { return !$0.belongsToAnApp }
            return $0.info.st_size != $1.info.st_size ? $0.info.st_size > $1.info.st_size : $0.path < $1.path
        }
        listing: for candidate in candidates {
            let url = URL(filePath: candidate.path)
            let hasRoom = results.files.count < maximumResults
            let judgment = judge(
                url, info: candidate.info, kind: kind, refusal: refusal, syncsToOtherDevices: syncsToOtherDevices
            )
            switch judgment {
            case .skipped:
                continue
            case .leftOut(let reason):
                // Counted only while the list had room: whatever came after was left out by the cut.
                if hasRoom { results.leftOut[reason, default: 0] += 1 }
            case .listed:
                guard hasRoom else {
                    results.isTruncated = true
                    break listing
                }
                results.files.append(FoundFile(
                    url: url,
                    size: ReclaimableSpace.of(url),
                    length: Int64(candidate.info.st_size),
                    modificationDate: Date(timeIntervalSince1970: TimeInterval(candidate.info.st_mtimespec.tv_sec)),
                    requiresPrivileges: FileAccess.requiresPrivilegesToRemove(url),
                    belongsToAnApp: candidate.belongsToAnApp,
                    identity: FileIdentity(candidate.info)
                ))
            }
        }
        // The longest made the list, which then goes by what moving each file frees.
        results.files.sort {
            if $0.belongsToAnApp != $1.belongsToAnApp { return !$0.belongsToAnApp }
            if $0.size != $1.size { return $0.size > $1.size }
            return $0.length != $1.length
                ? $0.length > $1.length : $0.url.path(percentEncoded: false) < $1.url.path(percentEncoded: false)
        }
        return results
    }

    static func judge(
        _ url: URL, info: stat, kind: FileKind, refusal: (URL) -> GuardRefusal?, syncsToOtherDevices: (URL) -> Bool
    ) -> Judgment {
        guard holdsItsContentsHere(info) else {
            // A transport stream is a movie only by its first bytes, and reading a file that lives only in the cloud
            // downloads it.
            return kind == .movies && isTypedAsATransportStream(url) ? .skipped : .leftOut(.syncs)
        }
        guard kind != .movies || isAMovie(url) else { return .skipped }
        guard let refused = refusal(url) else { return .listed }
        // That a file syncs is what the person needs to know, whatever else the guard says: a file in iCloud Drive
        // sits in a tree the guard protects.
        return .leftOut(refused == .inTheCloud || syncsToOtherDevices(url) ? .syncs : LeftOut(refused))
    }

    /// macOS gives TypeScript's `.ts` the type of an MPEG-2 transport stream, a movie, so such a file is one only when
    /// it begins as one: packets that each start with the byte 0x47, every 188 bytes, or every 192 after the 4-byte
    /// header Blu-ray adds (ISO/IEC 13818-1).
    static func isAMovie(_ url: URL) -> Bool {
        guard isTypedAsATransportStream(url) else { return true }
        guard let bytes = BoundedRead.prefix(of: url, count: 197).map(Array.init) else { return false }
        func packets(from start: Int, every length: Int) -> Bool {
            bytes.count > start + length && bytes[start] == 0x47 && bytes[start + length] == 0x47
        }
        return packets(from: 0, every: 188) || packets(from: 4, every: 192)
    }

    static func isTypedAsATransportStream(_ url: URL) -> Bool {
        UTType(filenameExtension: url.pathExtension) == .mpeg2TransportStream
    }

    /// Whether a file's contents are on this Mac. One whose contents live only in the cloud (`SF_DATALESS`) frees
    /// nothing here when moved.
    static func holdsItsContentsHere(_ info: stat) -> Bool {
        info.st_flags & UInt32(SF_DATALESS) == 0
    }

    /// The Library folder in the home folder, `/Library`, and `/System/Library`, where apps keep the data they work
    /// with. Each folder's names are read once, since a wide search asks about hundreds of thousands of paths.
    struct AppDataFolders {
        private let folders: [[String]]

        init(home: URL) {
            let library = PathPattern.comparablePath(of: home) + "/Library"
            folders = [library, "/Library", "/System/Library"].map(PathComponents.of)
        }

        /// Whether `path` sits inside one of the folders, compared name by name as `PathComponents` does.
        func holds(_ path: String) -> Bool {
            let names = PathComponents.of(path)
            return folders.contains { names.count > $0.count && names.starts(with: $0) }
        }
    }

    static func makeQuery(for criteria: FileSearchCriteria) -> MDQuery? {
        MDQueryCreate(kCFAllocatorDefault, queryString(for: criteria) as CFString, nil, nil)
    }

    static func queryString(for criteria: FileSearchCriteria) -> String {
        var clauses = [#"kMDItemContentTypeTree != "public.directory""#]
        if !criteria.trimmedName.isEmpty {
            clauses.append(nameClause(criteria.trimmedName))
        }
        if criteria.minimumSize > 0 {
            clauses.append("kMDItemFSSize >= \(criteria.minimumSize)")
        }
        if criteria.unmodifiedDays > 0 {
            clauses.append("kMDItemFSContentChangeDate < $time.today(-\(criteria.unmodifiedDays))")
        }
        if criteria.kind != .any {
            clauses.append(typeClause(for: criteria.kind))
        }
        return clauses.joined(separator: " && ")
    }

    /// Returns the Spotlight clause for file names that contain `name`. Spotlight folds case by the Mac's primary
    /// language, and Turkish folds `I` to `ı`, so on a Mac set to Turkish, `iina` would miss IINA. So besides the
    /// name as typed, each `i`, `I`, `ı`, or `İ` is asked for as `i` and as `I`, which between them match all four
    /// under either rule. Each such letter doubles the clause, so past four, only the name as typed is asked for.
    static func nameClause(_ name: String) -> String {
        let letters: Set<Character> = ["i", "I", "ı", "İ"]
        let count = name.filter { letters.contains($0) }.count
        guard count > 0, count <= 4 else { return "kMDItemFSName == \"*\(escaped(name))*\"cd" }
        var variants = [""]
        for character in name {
            variants = letters.contains(character)
                ? variants.flatMap { [$0 + "i", $0 + "I"] }
                : variants.map { $0 + String(character) }
        }
        let names = [name] + variants.filter { $0 != name }
        return "(" + names.map { "kMDItemFSName == \"*\(escaped($0))*\"cd" }.joined(separator: " || ") + ")"
    }

    /// Makes user text literal inside a quoted Spotlight value.
    static func escaped(_ text: String) -> String {
        var result = ""
        for character in text {
            if "\\\"*?".contains(character) {
                result.append("\\")
            }
            result.append(character)
        }
        return result
    }

    private static func typeClause(for kind: FileKind) -> String {
        var clause = kind.includedTypes.map { "kMDItemContentTypeTree == \"\($0.identifier)\"" }.joined(separator: " || ")
        if !kind.excludedTypes.isEmpty {
            clause = "(\(clause))" + kind.excludedTypes.map { " && kMDItemContentTypeTree != \"\($0.identifier)\"" }.joined()
        }
        return "(\(clause))"
    }
}

/// One Spotlight query, run without blocking a thread and stopped with the task that waits for it. It is only ever
/// touched on its own serial queue, where Spotlight also delivers its results.
private final class SpotlightGathering: @unchecked Sendable {
    private let query: MDQuery
    private let queue = DispatchQueue(label: "com.tuguidragos.Peel.FileSearch")
    // Touched only on `queue`.
    private var continuation: CheckedContinuation<[String]?, Never>?
    private var observer: (any NSObjectProtocol)?
    private var isOver = false
    /// Set as soon as the task is canceled, not on `queue`, where the cancel would wait behind the reading of paths.
    private let isCanceled = Atomic(false)

    init(_ query: MDQuery) {
        self.query = query
    }

    func paths() async -> [String]? {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                queue.async { self.start(continuation) }
            }
        } onCancel: {
            isCanceled.store(true, ordering: .relaxed)
            queue.async { self.end(with: nil) }
        }
    }

    private func start(_ continuation: CheckedContinuation<[String]?, Never>) {
        // Canceled before it started.
        guard !isOver else { return continuation.resume(returning: nil) }
        self.continuation = continuation
        MDQuerySetDispatchQueue(query, queue)
        observer = NotificationCenter.default.addObserver(
            forName: Notification.Name(kMDQueryDidFinishNotification as String), object: query, queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            end(with: foundPaths())
        }
        if !MDQueryExecute(query, 0) {
            end(with: nil)
        }
    }

    /// Reads each result's path from the result itself, since a query's value lists never carry `kMDItemPath`.
    /// Nil once the task is canceled.
    private func foundPaths() -> [String]? {
        MDQueryDisableUpdates(query)
        var paths: [String] = []
        for index in 0..<MDQueryGetResultCount(query) {
            if index.isMultiple(of: 256), isCanceled.load(ordering: .relaxed) { return nil }
            guard let pointer = MDQueryGetResultAtIndex(query, index) else { continue }
            let item = Unmanaged<MDItem>.fromOpaque(pointer).takeUnretainedValue()
            if let path = MDItemCopyAttribute(item, kMDItemPath) as? String {
                paths.append(path)
            }
        }
        return paths
    }

    /// Stops the query and answers the waiting task, once.
    private func end(with paths: [String]?) {
        guard !isOver else { return }
        isOver = true
        MDQueryStop(query)
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
        continuation?.resume(returning: paths)
        continuation = nil
    }
}
