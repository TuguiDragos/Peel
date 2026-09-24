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
    @concurrent
    public static func run(_ criteria: FileSearchCriteria, environment: SearchEnvironment = .current, exclusions: Exclusions = .none) async -> FileSearchResults {
        guard criteria.isSearchable, let query = makeQuery(for: criteria) else { return FileSearchResults(didRun: false) }
        let scope = criteria.scope == .home ? kMDQueryScopeHome : kMDQueryScopeComputer
        MDQuerySetSearchScope(query, [scope] as CFArray, 0)

        guard MDQueryExecute(query, CFOptionFlags(kMDQuerySynchronous.rawValue)) else { return FileSearchResults(didRun: false) }

        let count = MDQueryGetResultCount(query)
        let paths = (0..<count).compactMap { index -> String? in
            guard let pointer = MDQueryGetResultAtIndex(query, index) else { return nil }
            return MDItemCopyAttribute(Unmanaged<MDItem>.fromOpaque(pointer).takeUnretainedValue(), kMDItemPath) as? String
        }
        return results(from: paths, environment: environment, exclusions: exclusions)
    }

    /// Turns the paths Spotlight found into results: checked on disk, sorted, and cut to `maximumResults`. It is
    /// separate from the query so a test can pass its own paths instead of relying on the Spotlight index.
    static func results(
        from paths: [String],
        environment: SearchEnvironment = .current,
        exclusions: Exclusions = .none
    ) -> FileSearchResults {
        let removalGuard = RemovalGuard(environment: environment, exclusions: exclusions)
        var results = FileSearchResults()
        for path in paths {
            var info = stat()
            guard lstat(path, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { continue }
            let url = URL(filePath: path)
            guard removalGuard.allowsRemoval(of: url) else { continue }
            results.files.append(FoundFile(
                url: url,
                size: Int64(info.st_size),
                modificationDate: Date(timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec)),
                requiresPrivileges: FileAccess.requiresPrivilegesToRemove(url),
                belongsToAnApp: isAppData(url, home: environment.homeDirectory),
                identity: FileIdentity(info)
            ))
        }
        // What an app keeps for itself goes last: the tool is for finding what the user made.
        results.files.sort {
            if $0.belongsToAnApp != $1.belongsToAnApp { return !$0.belongsToAnApp }
            return $0.size != $1.size ? $0.size > $1.size : $0.url.path(percentEncoded: false) < $1.url.path(percentEncoded: false)
        }
        // Cut after the sort: `MDQuery.h` promises no order, so cutting first would keep an arbitrary set of
        // files rather than the largest.
        if results.files.count > maximumResults {
            results.files = Array(results.files.prefix(maximumResults))
            results.isTruncated = true
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
