import CoreServices
import Darwin
public import Foundation
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

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct FoundFile: Sendable, Hashable, Identifiable {
    public let url: URL
    public let size: Int64
    public let modificationDate: Date
    public let requiresPrivileges: Bool
    /// True when the file sits in a Library folder, so it is an app's working data rather than something the user
    /// made. Such a file is listed last and never selected for the user.
    public var belongsToAnApp = false
    /// The file's identity when it was listed. Results can stay on screen for a long time, and a file written
    /// again under the same name is not the one the row describes.
    public var identity: FileIdentity?

    public var id: URL { url }
}

public struct FileSearchResults: Sendable {
    public var files: [FoundFile] = []
    /// True when more than `FileSearch.maximumResults` files were found and the list was cut to that many.
    public var isTruncated = false
    /// False when the query itself could not be made or run, which is not the same as finding nothing.
    public var didRun = true
}

public enum FileSearch {
    public static let maximumResults = 2_000

    /// Runs a Spotlight query and returns the paths it found, or nil when it could not run or was stopped.
    typealias Gather = @concurrent @Sendable (sending MDQuery) async -> [String]?

    /// Moves `files` to the Trash. A file written again under the same name after it was listed is a different
    /// file, so it fails with `changedSinceScan` instead.
    @concurrent
    public static func trash(_ files: [FoundFile], using trashService: TrashService) async -> TrashResult {
        var result = TrashResult()
        for file in files {
            guard let identity = file.identity, FileIdentity.of(file.url)?.holdsTheSameContents(as: identity) == true else {
                result.failures.append(TrashFailure(url: file.url, reason: .changedSinceScan))
                continue
            }
            let moved = await trashService.trash([file.url])
            result.trashed += moved.trashed
            result.failures += moved.failures
        }
        return result
    }

    /// Returns up to `maximumResults` regular files from the Spotlight index that match `criteria` and that the
    /// removal guard allows. Files in a Library folder come after the rest, and each part is sorted largest first.
    /// Stopping the task stops the query.
    @concurrent
    public static func run(_ criteria: FileSearchCriteria, environment: SearchEnvironment = .current, exclusions: Exclusions = .none) async -> FileSearchResults {
        await run(criteria, environment: environment, exclusions: exclusions) { await SpotlightGathering($0).paths() }
    }

    /// The same, with the query run by `gather`, so a test can stand in for one that never finishes.
    static func run(
        _ criteria: FileSearchCriteria,
        environment: SearchEnvironment = .current,
        exclusions: Exclusions = .none,
        gather: Gather
    ) async -> FileSearchResults {
        guard criteria.isSearchable, let query = makeQuery(for: criteria) else { return FileSearchResults(didRun: false) }
        let scope = criteria.scope == .home ? kMDQueryScopeHome : kMDQueryScopeComputer
        MDQuerySetSearchScope(query, [scope] as CFArray, 0)
        guard let paths = await gather(query), !Task.isCancelled else { return FileSearchResults(didRun: false) }
        return results(from: paths, environment: environment, exclusions: exclusions)
    }

    /// Turns the paths Spotlight found into results: checked on disk, sorted, and cut to `maximumResults`. It is
    /// separate from the query so a test can pass its own paths, and its own answer in place of the guard's.
    static func results(
        from paths: [String],
        environment: SearchEnvironment = .current,
        exclusions: Exclusions = .none,
        allows: ((URL) -> Bool)? = nil
    ) -> FileSearchResults {
        let allows = allows ?? RemovalGuard(environment: environment, exclusions: exclusions).allowsRemoval(of:)
        var candidates: [(url: URL, info: stat, belongsToAnApp: Bool)] = []
        for path in paths {
            guard !Task.isCancelled else { return FileSearchResults(didRun: false) }
            var info = stat()
            guard lstat(path, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { continue }
            let url = URL(filePath: path)
            candidates.append((url, info, isAppData(url, home: environment.homeDirectory)))
        }
        // In the list's order before the guard is asked, so it is asked only about files that can make the list.
        // What an app keeps for itself goes last: the tool is for finding what the user made.
        candidates.sort {
            if $0.belongsToAnApp != $1.belongsToAnApp { return !$0.belongsToAnApp }
            return $0.info.st_size != $1.info.st_size
                ? $0.info.st_size > $1.info.st_size
                : $0.url.path(percentEncoded: false) < $1.url.path(percentEncoded: false)
        }
        var results = FileSearchResults()
        for candidate in candidates where allows(candidate.url) {
            guard results.files.count < maximumResults else {
                results.isTruncated = true
                break
            }
            results.files.append(FoundFile(
                url: candidate.url,
                size: Int64(candidate.info.st_size),
                modificationDate: Date(timeIntervalSince1970: TimeInterval(candidate.info.st_mtimespec.tv_sec)),
                requiresPrivileges: FileAccess.requiresPrivilegesToRemove(candidate.url),
                belongsToAnApp: candidate.belongsToAnApp,
                identity: FileIdentity(candidate.info)
            ))
        }
        return results
    }

    /// Returns whether `url` is inside the Library folder in `home`, `/Library`, or `/System/Library`, where apps
    /// keep the data they work with.
    static func isAppData(_ url: URL, home: URL) -> Bool {
        let path = PathPattern.comparablePath(of: url)
        return [PathPattern.comparablePath(of: home) + "/Library", "/Library", "/System/Library"].contains {
            PathComponents.isPath(path, inside: $0)
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
            variants = letters.contains(character) ? variants.flatMap { [$0 + "i", $0 + "I"] } : variants.map { $0 + String(character) }
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

    init(_ query: MDQuery) {
        self.query = query
    }

    func paths() async -> [String]? {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                queue.async { self.start(continuation) }
            }
        } onCancel: {
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
    private func foundPaths() -> [String] {
        MDQueryDisableUpdates(query)
        return (0..<MDQueryGetResultCount(query)).compactMap { index in
            guard let pointer = MDQueryGetResultAtIndex(query, index) else { return nil }
            let item = Unmanaged<MDItem>.fromOpaque(pointer).takeUnretainedValue()
            return MDItemCopyAttribute(item, kMDItemPath) as? String
        }
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
