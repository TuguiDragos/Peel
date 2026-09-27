public import Foundation
internal import PeelPrivileged

/// A folder that a build or a package manager leaves inside a project, such as `node_modules`, `target`, or
/// `Pods`. It only counts when the project file behind it sits beside it (`package.json` for `node_modules`),
/// so a folder called `build` that no tool made is left alone.
public struct ProjectArtifact: Sendable, Hashable, Identifiable {
    public let url: URL
    /// The project folder the artifact belongs to.
    public let project: URL
    public let name: String
    public let tool: String
    /// Nil when measuring ran out of time or was refused. Unknown is not the same as empty.
    public let size: Int64?
    /// The latest change found in the project's own files, leaving out its artifacts.
    public let lastActivity: Date?
    /// False when Peel could not tell when the project last changed: it was too big to read to the end, or
    /// nothing in it had a date. What is not known is never selected for the user.
    public var lastActivityIsCertain = true
    /// True for folders whose name says nothing on its own, like `build` or `target`.
    public let hasGenericName: Bool
    /// True for an installed set of packages, which a build doesn't make again on its own.
    public let isEnvironment: Bool
    /// Why what measuring the folder saw leaves it to be chosen by hand: it was not measured or not read, or a
    /// wallet or a repository is inside. Nil when nothing did.
    public var heldBack: HoldBack?

    public var id: URL { url }

    public var isRecentlyActive: Bool {
        guard let lastActivity else { return false }
        return lastActivity > Date.now.addingTimeInterval(-ProjectArtifacts.recentlyActive)
    }

    /// Whether Peel selects this artifact for the user: build output with a name that can't mean anything
    /// else, in a project known not to have changed lately, measured, and holding nothing that may exist nowhere
    /// else.
    public var isRecommended: Bool {
        !hasGenericName && !isEnvironment && !isRecentlyActive && lastActivityIsCertain && heldBack == nil
    }
}

public enum ProjectArtifacts {
    /// A project changed within this time counts as in use, so none of its artifacts are selected for the user.
    public static let recentlyActive: TimeInterval = 7 * 24 * 60 * 60

    /// The artifacts a mark leaving them out of Time Machine goes on: only what Peel is sure a build makes again,
    /// since a folder with a generic name like `build` could be the user's own and the mark travels with the
    /// folder, even into a copy of it (`man tmutil`). An artifact Time Machine already leaves out through a
    /// folder above it is skipped too: it has no mark of its own to change.
    public static func markableForBackups(_ artifacts: [ProjectArtifact], excludedFromAbove: Set<URL>) -> [URL] {
        artifacts.filter { !$0.hasGenericName && !excludedFromAbove.contains($0.url) }.map(\.url)
    }

    struct Definition: Sendable {
        let name: String
        /// The artifact only counts when one of these sits beside it. A leading `*` matches any name with
        /// that ending, as in `*.xcodeproj`.
        let markers: [String]
        let tool: String
        /// A name that could mean anything, so it is shown but never preselected.
        let isGeneric: Bool
        /// Installed packages rather than build output, so it is shown but never preselected.
        var isEnvironment = false
    }

    static let definitions: [Definition] = [
        Definition(name: "node_modules", markers: ["package.json"], tool: "npm", isGeneric: false),
        Definition(name: ".build", markers: ["Package.swift"], tool: "Swift Package Manager", isGeneric: false),
        Definition(name: "Pods", markers: ["Podfile"], tool: "CocoaPods", isGeneric: false),
        Definition(name: "Carthage", markers: ["Cartfile"], tool: "Carthage", isGeneric: false),
        Definition(name: "DerivedData", markers: ["*.xcodeproj", "*.xcworkspace"], tool: "Xcode", isGeneric: false),
        Definition(name: ".next", markers: ["next.config.js", "next.config.mjs", "next.config.ts"], tool: "Next.js", isGeneric: false),
        Definition(name: ".dart_tool", markers: ["pubspec.yaml"], tool: "Dart & Flutter", isGeneric: false),
        // `.terraform` keeps the selected workspace and the last backend configuration beside the cached
        // providers, and `terraform init` brings back only the providers.
        Definition(name: ".terraform", markers: ["*.tf"], tool: "Terraform", isGeneric: false, isEnvironment: true),
        Definition(name: ".gradle", markers: ["build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts"], tool: "Gradle", isGeneric: false),
        Definition(name: "target", markers: ["Cargo.toml"], tool: "Cargo", isGeneric: true),
        Definition(name: "target", markers: ["pom.xml"], tool: "Maven", isGeneric: true),
        Definition(name: "build", markers: ["build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts"], tool: "Gradle", isGeneric: true),
        Definition(name: "build", markers: ["pubspec.yaml"], tool: "Dart & Flutter", isGeneric: true),
        Definition(name: ".venv", markers: ["pyproject.toml", "requirements.txt", "Pipfile", "setup.py"], tool: "Python", isGeneric: false, isEnvironment: true),
        Definition(name: "venv", markers: ["pyproject.toml", "requirements.txt", "Pipfile", "setup.py"], tool: "Python", isGeneric: false, isEnvironment: true),
    ]

    /// Returns whether `name` is one of the markers in `definitions`, such as `package.json` or
    /// `App.xcodeproj`. Duplicates uses it to recognize a project folder and leave it alone.
    static func isMarker(_ name: String) -> Bool {
        exactMarkers.contains(name) || markerSuffixes.contains { name.hasSuffix($0) && name.count > $0.count }
    }

    private static let exactMarkers = Set(definitions.flatMap(\.markers).filter { !$0.hasPrefix("*") })
    private static let markerSuffixes = Set(definitions.flatMap(\.markers).filter { $0.hasPrefix("*") }.map { String($0.dropFirst()) })

    /// A scan never walks deeper than this, and never into an artifact it has already found.
    static let maximumDepth = 8
    static let maximumFolders = 40_000
    /// How many of a project's entries are read, at most, to find its last change. When the walk reaches
    /// this limit, the last change counts as unknown.
    static let maximumActivitySamples = 2_000

    /// The result of one scan of the chosen folders. `wasCutShort` is true when the scan reached
    /// `maximumFolders` and left the deepest folders unread, so the page can say the list is incomplete.
    public struct Scan: Sendable {
        public var artifacts: [ProjectArtifact] = []
        public var wasCutShort = false
        /// The chosen folders macOS refused, which Full Disk Access would open.
        public var unreadableLocations: [URL] = []

        public var needsFullDiskAccess: Bool { !unreadableLocations.isEmpty }
    }

    @concurrent
    public static func scan(roots: [URL], exclusions: Exclusions = .none) async -> Scan {
        await scan(roots: roots, exclusions: exclusions, measure: LeftoverScanner.walk)
    }

    @concurrent
    static func scan(roots: [URL], exclusions: Exclusions, measure: @escaping LeftoverScanner.Measure) async -> Scan {
        await withTaskGroup(of: (artifacts: [ProjectArtifact], wasCutShort: Bool).self) { group in
            for root in roots where isSearchable(root) {
                group.addTask { await artifacts(in: root, exclusions: exclusions, measure: measure) }
            }
            var found: [ProjectArtifact] = []
            var seen: Set<URL> = []
            var wasCutShort = false
            for await result in group {
                wasCutShort = wasCutShort || result.wasCutShort
                for artifact in result.artifacts where seen.insert(artifact.url).inserted {
                    found.append(artifact)
                }
            }
            return Scan(
                artifacts: found.sorted { SizeTotal([$0.size]) > SizeTotal([$1.size]) },
                wasCutShort: wasCutShort,
                unreadableLocations: roots.filter { isSearchable($0) && FullDiskAccess.canList($0) == .missing }
            )
        }
    }

    /// Why a chosen folder cannot be searched. The page shows the reason instead of an empty list.
    public enum Refusal: Sendable, Hashable {
        case tooBroad
        case inTheCloud
        case notAFolder
    }

    /// Returns why `root` cannot be searched, or nil when it can. A whole volume or a home folder is too broad
    /// to walk, and a cloud folder is left to the app that syncs it. Every spelling of the path is checked, as
    /// the removal guard and the exclusions do: `/users/me` and `/System/Volumes/Data/Users/me` are the same
    /// home folder, and a link into a cloud folder is that cloud folder.
    public static func refusal(for root: URL, home: URL = .homeDirectory) -> Refusal? {
        let spellings = ([PathPattern.comparablePath(of: root), PathPattern.canonical(root).path(percentEncoded: false)]
            + Array(PathPattern.spellings(of: PathPattern.comparablePath(of: root)))).map { $0.lowercased() }
        let homes = ([PathPattern.comparablePath(of: home), PathPattern.canonical(home).path(percentEncoded: false)]
            + Array(PathPattern.spellings(of: PathPattern.comparablePath(of: home)))).map { spelling in
                var path = spelling.lowercased()
                while path.count > 1, path.hasSuffix("/") { path.removeLast() }
                return path
            }

        for spelling in spellings {
            var path = spelling
            while path.count > 1, path.hasSuffix("/") { path.removeLast() }
            if path.contains("/library/mobile documents") || path.contains("/library/cloudstorage") { return .inTheCloud }
            let components = PathComponents.of(path)
            // Too broad: the root and every top-level folder, anyone's home folder, and the root of any volume.
            // A home folder and a volume root both have two components, so they are recognized by name.
            if components.count < 2 || homes.contains(path) { return .tooBroad }
            if components.count == 2, ["users", "volumes"].contains(components[0]) { return .tooBroad }
            if path == "/system/volumes/data" { return .tooBroad }
            if components.count == 5, components.starts(with: ["system", "volumes", "data", "users"]) { return .tooBroad }
        }

        var isDirectory: ObjCBool = false
        let isThere = FileManager.default.fileExists(atPath: PathPattern.comparablePath(of: root), isDirectory: &isDirectory) && isDirectory.boolValue
        return isThere ? nil : .notAFolder
    }

    static func isSearchable(_ root: URL, home: URL = .homeDirectory) -> Bool {
        refusal(for: root, home: home) == nil
    }

    static func artifacts(in root: URL, exclusions: Exclusions, measure: LeftoverScanner.Measure) async -> (artifacts: [ProjectArtifact], wasCutShort: Bool) {
        var found: [ProjectArtifact] = []
        var queue: [(url: URL, depth: Int)] = [(root, 0)]
        // An index rather than `removeFirst`, which shifts every waiting folder on each call and makes the
        // scan quadratic.
        var next = 0
        var visited = 0

        while next < queue.count, visited < maximumFolders, !Task.isCancelled {
            let (folder, depth) = queue[next]
            next += 1
            visited += 1
            guard let entries = contents(of: folder) else { continue }
            let names = Set(entries.map(\.lastPathComponent))
            var artifactNames: Set<String> = []

            var matching: [Definition] = []
            for definition in definitions where names.contains(definition.name) {
                let url = folder.appending(path: definition.name)
                guard isRealFolder(url), marker(for: definition, in: names) != nil else { continue }
                guard !exclusions.excludes(url), !exclusions.holds(url) else { continue }
                guard artifactNames.insert(definition.name).inserted else { continue }
                matching.append(definition)
            }
            // Read once per project, after all of its artifacts are found, so the walk skips every one of them.
            let activity = matching.isEmpty ? (date: nil, isCertain: true) : lastActivity(in: folder, ignoring: artifactNames)
            for definition in matching {
                let url = folder.appending(path: definition.name)
                let contents = await measure(url)
                let heldBack = HoldBack.seen(in: contents)
                found.append(ProjectArtifact(
                    url: url,
                    project: folder,
                    name: definition.name,
                    tool: definition.tool,
                    size: contents.flatMap { $0.couldNotBeRead ? nil : $0.size },
                    lastActivity: activity.date,
                    lastActivityIsCertain: activity.isCertain,
                    hasGenericName: definition.isGeneric,
                    isEnvironment: definition.isEnvironment,
                    // A tool that tags its folder as a cache makes everything in it again, its own clones included.
                    heldBack: heldBack == .holdsRepository && isTaggedAsACache(url) ? nil : heldBack
                ))
            }

            guard depth < maximumDepth else { continue }
            for entry in entries where !artifactNames.contains(entry.lastPathComponent) {
                guard isRealFolder(entry), !exclusions.excludes(entry), !isSkipped(entry.lastPathComponent) else { continue }
                queue.append((entry, depth + 1))
            }
        }
        return (found, next < queue.count)
    }

    /// Returns whether a walk skips an entry called `name`: anything hidden, `Library`, or an artifact's name.
    /// Projects live in visible folders, and a hidden folder is usually a tool's own store, such as `~/.npm`
    /// with its many `node_modules`, which belong to the Developer page.
    static func isSkipped(_ name: String) -> Bool {
        if name.hasPrefix(".") || name == "Library" { return true }
        return definitions.contains { $0.name == name }
    }

    static func marker(for definition: Definition, in names: Set<String>) -> String? {
        for marker in definition.markers {
            if marker.hasPrefix("*") {
                let suffix = String(marker.dropFirst())
                if let match = names.first(where: { $0.hasSuffix(suffix) && $0.count > suffix.count }) { return match }
            } else if names.contains(marker) {
                return marker
            }
        }
        return nil
    }

    /// Files Git updates whenever the repository changes. They are read first: three reads can answer for a
    /// whole repository, where the walk below reads only a sample of the project's files.
    private static let gitMarks = [".git/index", ".git/HEAD", ".git/logs/HEAD"]

    /// Returns the latest change found in the project, leaving out its artifacts. It stops at the first change
    /// within `recentlyActive`, which alone answers the question. `isCertain` is false when the walk was cut
    /// short or found no date at all.
    static func lastActivity(in project: URL, ignoring artifacts: Set<String>) -> (date: Date?, isCertain: Bool) {
        let cutoff = Date.now.addingTimeInterval(-recentlyActive)
        var newest: Date?
        for mark in gitMarks {
            let url = project.appending(path: mark)
            guard let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else { continue }
            if newest == nil || date > newest! { newest = date }
            if date > cutoff { return (date, true) }
        }

        guard let enumerator = FileManager.default.enumerator(
            at: project,
            includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
            options: [.skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else { return (newest, newest != nil) }

        var samples = 0
        for case let url as URL in enumerator {
            let name = url.lastPathComponent
            if artifacts.contains(name) || isSkipped(name) {
                enumerator.skipDescendants()
                continue
            }
            samples += 1
            guard samples <= maximumActivitySamples else { return (newest, false) }
            guard let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else { continue }
            if newest == nil || date > newest! { newest = date }
            if date > cutoff { return (date, true) }
        }
        return (newest, newest != nil)
    }

    /// Whether `folder` carries a cache directory tag, with which its tool says that everything inside can be made
    /// again. The Cache Directory Tagging Specification has the file begin with this signature. Swift Package
    /// Manager tags `.build`, which `swift package reset` deletes whole and `swift package resolve` clones again.
    static func isTaggedAsACache(_ folder: URL) -> Bool {
        let signature = Data("Signature: 8a477f597d28d172789f06886806bc55".utf8)
        guard let tag = BoundedRead.data(at: folder.appending(path: "CACHEDIR.TAG"), maximum: 4_096) else { return false }
        return tag.starts(with: signature)
    }

    /// Returns whether `url` is a plain folder: not a link, a package, or a cloud item. A cloud placeholder
    /// looks like a folder but holds nothing until it is downloaded. A package can be an app: an Electron app
    /// ships `package.json` beside `node_modules` inside its bundle, and nothing may be removed from there.
    static func isRealFolder(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isUbiquitousItemKey, .isPackageKey])
        guard values?.isDirectory == true, values?.isSymbolicLink != true, values?.isPackage != true else { return false }
        return values?.isUbiquitousItem != true
    }

    private static func contents(of folder: URL) -> [URL]? {
        let entries = try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isUbiquitousItemKey, .isPackageKey],
            options: []
        )
        ScanCount.current?.add(entries?.count ?? 0)
        return entries
    }
}

extension ProjectArtifact {
    /// Returns whether `query` matches the folder's name, the tool that made it, or the project's name, which
    /// are what a row shows.
    public func matches(_ query: String) -> Bool {
        guard !query.isEmpty else { return true }
        return SearchText.matches(name, query)
            || SearchText.matches(tool, query)
            || SearchText.matches(project.lastPathComponent, query)
    }
}
