public import Foundation
internal import PeelPrivileged

/// A folder a build or a package manager leaves inside a project. It counts only when the project file behind it
/// sits beside it (`package.json` for `node_modules`), so a `build` folder no tool made is left alone.
public struct ProjectArtifact: Sendable, Hashable, Identifiable {
    public let url: URL
    public let project: URL
    public let name: String
    public let tool: String
    /// Nil when it was not measured, which is not the same as empty.
    public let size: Int64?
    /// The latest change in the project's own files, its artifacts left out.
    public let lastActivity: Date?
    public var lastActivityIsCertain = true
    /// A name that says nothing on its own, like `build` or `target`: shown, never selected for the user.
    public let hasGenericName: Bool
    /// Installed packages, which a build does not make again on its own: shown, never selected for the user.
    public let isEnvironment: Bool
    public var heldBack: HoldBack?

    public var id: URL { url }

    public var isRecentlyActive: Bool {
        guard let lastActivity else { return false }
        return lastActivity > Date.now.addingTimeInterval(-ProjectArtifacts.recentlyActive)
    }

    public var isRecommended: Bool {
        !hasGenericName && !isEnvironment && !isRecentlyActive && lastActivityIsCertain && heldBack == nil
    }
}

public enum ProjectArtifacts {
    /// A project changed within this time is in use, so none of its artifacts are selected for the user.
    public static let recentlyActive: TimeInterval = 7 * 24 * 60 * 60

    /// The artifacts to leave out of Time Machine: never one with a generic name, since the mark travels with the
    /// folder, even into a copy of it (`man tmutil`).
    public static func markableForBackups(_ artifacts: [ProjectArtifact], excludedFromAbove: Set<URL>) -> [URL] {
        artifacts.filter { !$0.hasGenericName && !excludedFromAbove.contains($0.url) }.map(\.url)
    }

    struct Definition: Sendable {
        let name: String
        /// A leading `*` matches any name with that ending, as in `*.xcodeproj`.
        let markers: [String]
        let tool: String
        let isGeneric: Bool
        var isEnvironment = false
        /// Where the tool documents the folder: a page, or what Xcode itself prints.
        let source: String
        /// What the folder holds that only its tool writes, for a kind no project file stands beside.
        var proof: Proof?

        /// Whether the folder at `url`, beside the entries called `names`, is this kind.
        func matches(_ url: URL, besides names: Set<String>) -> Bool {
            guard markers.isEmpty || ProjectArtifacts.marker(for: self, in: names) != nil else { return false }
            return proof?.holds(at: url) ?? true
        }
    }

    enum Proof: Sendable {
        /// A file the tool always writes inside, as `venv` writes `pyvenv.cfg`.
        case holds(String)
        /// Nothing but files with this ending, as Python writes only compiled `.pyc` files into `__pycache__`.
        case holdsOnlyFilesEnding(String)

        func holds(at url: URL) -> Bool {
            switch self {
            case .holds(let name):
                var info = stat()
                let path = url.appending(path: name).path(percentEncoded: false)
                return lstat(path, &info) == 0 && info.st_mode & S_IFMT == S_IFREG
            case .holdsOnlyFilesEnding(let ending):
                let entries = (try? FileManager.default.contentsOfDirectory(
                    at: url, includingPropertiesForKeys: [.isRegularFileKey]
                )) ?? []
                return !entries.isEmpty && entries.allSatisfy { entry in
                    entry.lastPathComponent.hasSuffix(ending)
                        && (try? entry.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
                }
            }
        }
    }

    private static let gradleFiles = ["build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts"]
    private static let pythonProjectFiles = ["pyproject.toml", "requirements.txt", "Pipfile", "setup.py"]
    private static let nextConfigFiles = ["next.config.js", "next.config.mjs", "next.config.ts"]
    private static let nuxtConfigFiles = ["nuxt.config.ts", "nuxt.config.js", "nuxt.config.mjs"]
    private static let viteConfigFiles = ["ts", "mts", "cts", "js", "mjs", "cjs"].map { "vite.config." + $0 }
    private static let vitestConfigFiles = ["ts", "mts", "cts", "js", "mjs", "cjs"].map { "vitest.config." + $0 }
    private static let gatsbyConfigFiles = ["gatsby-config.js", "gatsby-config.ts", "gatsby-config.mjs"]
    private static let pytestFiles = [
        "pytest.toml", ".pytest.toml", "pytest.ini", ".pytest.ini", "pyproject.toml", "tox.ini", "setup.cfg",
        "conftest.py",
    ]

    static let definitions: [Definition] = [
        Definition(
            name: "node_modules", markers: ["package.json"], tool: "npm", isGeneric: false,
            source: "https://docs.npmjs.com/cli/v11/configuring-npm/folders"
        ),
        Definition(
            name: ".build", markers: ["Package.swift"], tool: "Swift Package Manager", isGeneric: false,
            source: "Xcode 27: swift build --help (--scratch-path, default .build)"
        ),
        Definition(
            name: "Pods", markers: ["Podfile"], tool: "CocoaPods", isGeneric: false,
            source: "https://guides.cocoapods.org/using/using-cocoapods.html"
        ),
        Definition(
            name: "Carthage", markers: ["Cartfile"], tool: "Carthage", isGeneric: false,
            source: "https://github.com/Carthage/Carthage/blob/master/README.md"
        ),
        Definition(
            name: "DerivedData", markers: ["*.xcodeproj", "*.xcworkspace"], tool: "Xcode", isGeneric: false,
            source: "Xcode 27: man xcodebuild (-derivedDataPath)"
        ),
        Definition(
            name: ".next", markers: nextConfigFiles, tool: "Next.js", isGeneric: false,
            source: "https://nextjs.org/docs/app/api-reference/config/next-config-js/distDir"
        ),
        Definition(
            name: ".nuxt", markers: nuxtConfigFiles, tool: "Nuxt", isGeneric: false,
            source: "https://nuxt.com/docs/4.x/directory-structure/nuxt"
        ),
        Definition(
            name: ".output", markers: nuxtConfigFiles, tool: "Nuxt", isGeneric: false,
            source: "https://nuxt.com/docs/4.x/directory-structure/output"
        ),
        Definition(
            name: ".svelte-kit", markers: ["svelte.config.js"], tool: "SvelteKit", isGeneric: false,
            source: "https://svelte.dev/docs/kit/project-structure"
        ),
        Definition(
            name: ".angular", markers: ["angular.json"], tool: "Angular", isGeneric: false,
            source: "https://angular.dev/cli/cache"
        ),
        Definition(
            name: ".turbo", markers: ["turbo.json"], tool: "Turborepo", isGeneric: false,
            source: "https://turborepo.dev/docs/crafting-your-repository/caching"
        ),
        Definition(
            name: ".parcel-cache", markers: ["package.json"], tool: "Parcel", isGeneric: false,
            source: "https://parceljs.org/features/cli/"
        ),
        Definition(
            name: "storybook-static", markers: [".storybook"], tool: "Storybook", isGeneric: false,
            source: "https://github.com/storybookjs/storybook/blob/next/code/core/src/cli/build.ts"
        ),
        Definition(
            name: "dist", markers: viteConfigFiles, tool: "Vite", isGeneric: true,
            source: "https://vite.dev/config/build-options"
        ),
        Definition(
            name: "out", markers: nextConfigFiles, tool: "Next.js", isGeneric: true,
            source: "https://nextjs.org/docs/app/guides/static-exports"
        ),
        Definition(
            name: "coverage", markers: vitestConfigFiles, tool: "Vitest", isGeneric: true,
            source: "https://vitest.dev/config/coverage"
        ),
        Definition(
            name: ".cache", markers: gatsbyConfigFiles, tool: "Gatsby", isGeneric: true,
            source: "https://www.gatsbyjs.com/docs/reference/gatsby-cli/"
        ),
        Definition(
            name: "public", markers: gatsbyConfigFiles, tool: "Gatsby", isGeneric: true,
            source: "https://www.gatsbyjs.com/docs/reference/gatsby-cli/"
        ),
        Definition(
            name: ".dart_tool", markers: ["pubspec.yaml"], tool: "Dart & Flutter", isGeneric: false,
            source: "https://dart.dev/tools/pub/package-layout"
        ),
        // `.terraform` keeps the selected workspace and the last backend configuration beside the cached
        // providers, and `terraform init` brings back only the providers.
        Definition(
            name: ".terraform", markers: ["*.tf"], tool: "Terraform", isGeneric: false, isEnvironment: true,
            source: "https://developer.hashicorp.com/terraform/cli/init"
        ),
        Definition(
            name: ".gradle", markers: gradleFiles, tool: "Gradle", isGeneric: false,
            source: "https://docs.gradle.org/current/userguide/directory_layout.html"
        ),
        Definition(
            name: "target", markers: ["Cargo.toml"], tool: "Cargo", isGeneric: true,
            source: "https://doc.rust-lang.org/cargo/reference/build-cache.html"
        ),
        Definition(
            name: "target", markers: ["pom.xml"], tool: "Maven", isGeneric: true,
            source: "https://maven.apache.org/guides/introduction/introduction-to-the-standard-directory-layout.html"
        ),
        Definition(
            name: "build", markers: gradleFiles, tool: "Gradle", isGeneric: true,
            source: "https://docs.gradle.org/current/userguide/directory_layout.html"
        ),
        Definition(
            name: "build", markers: ["pubspec.yaml"], tool: "Dart & Flutter", isGeneric: true,
            source: "https://docs.flutter.dev/reference/flutter-cli"
        ),
        Definition(
            name: ".venv", markers: pythonProjectFiles, tool: "Python", isGeneric: false, isEnvironment: true,
            source: "https://docs.python.org/3/library/venv.html"
        ),
        Definition(
            name: "venv", markers: pythonProjectFiles, tool: "Python", isGeneric: false, isEnvironment: true,
            source: "https://docs.python.org/3/library/venv.html"
        ),
        Definition(
            name: "env", markers: pythonProjectFiles, tool: "Python", isGeneric: true, isEnvironment: true,
            source: "https://docs.python.org/3/library/venv.html", proof: .holds("pyvenv.cfg")
        ),
        Definition(
            name: "__pycache__", markers: [], tool: "Python", isGeneric: false,
            source: "https://docs.python.org/3/tutorial/modules.html", proof: .holdsOnlyFilesEnding(".pyc")
        ),
        Definition(
            name: ".pytest_cache", markers: pytestFiles, tool: "pytest", isGeneric: false,
            source: "https://docs.pytest.org/en/stable/how-to/cache.html"
        ),
        Definition(
            name: ".mypy_cache", markers: ["mypy.ini", ".mypy.ini", "pyproject.toml", "setup.cfg"], tool: "mypy",
            isGeneric: false, source: "https://mypy.readthedocs.io/en/stable/command_line.html"
        ),
        Definition(
            name: ".ruff_cache", markers: ["pyproject.toml", "ruff.toml", ".ruff.toml"], tool: "Ruff", isGeneric: false,
            source: "https://docs.astral.sh/ruff/settings/"
        ),
        Definition(
            name: "htmlcov", markers: [".coveragerc", "pyproject.toml", "setup.cfg", "tox.ini"], tool: "Coverage.py",
            isGeneric: false, source: "https://coverage.readthedocs.io/en/latest/config.html"
        ),
        Definition(
            name: ".tox", markers: ["tox.ini", "tox.toml", "pyproject.toml", "setup.cfg"], tool: "tox",
            isGeneric: false, isEnvironment: true, source: "https://tox.wiki/en/latest/reference/config.html"
        ),
        Definition(
            name: ".nox", markers: ["noxfile.py"], tool: "Nox", isGeneric: false, isEnvironment: true,
            source: "https://nox.thea.codes/en/stable/usage.html"
        ),
        Definition(
            name: "dist", markers: ["pyproject.toml"], tool: "Python", isGeneric: true,
            source: "https://packaging.python.org/en/latest/tutorials/packaging-projects/"
        ),
    ]

    /// Duplicates uses it to recognize a project folder and leave it alone.
    static func isMarker(_ name: String) -> Bool {
        exactMarkers.contains(name) || markerSuffixes.contains { name.hasSuffix($0) && name.count > $0.count }
    }

    private static let exactMarkers = Set(definitions.flatMap(\.markers).filter { !$0.hasPrefix("*") })
    private static let markerSuffixes = Set(definitions.flatMap(\.markers).filter { $0.hasPrefix("*") }.map { String($0.dropFirst()) })

    static let maximumDepth = 8
    static let maximumFolders = 40_000
    /// Past this many entries read, a project's last change counts as unknown.
    static let maximumActivitySamples = 2_000

    public struct Scan: Sendable {
        public var artifacts: [ProjectArtifact] = []
        /// True when the scan reached `maximumFolders` and left the deepest folders unread.
        public var wasCutShort = false
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

    public enum Refusal: Sendable, Hashable {
        case tooBroad
        case inTheCloud
        case notAFolder
    }

    /// Why `root` cannot be searched, or nil. Every spelling of the path is checked: `/users/me` and
    /// `/System/Volumes/Data/Users/me` are the same home folder, and a link into a cloud folder is that cloud folder.
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
        // An index, since `removeFirst` would make the walk quadratic.
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
                guard isRealFolder(url), definition.matches(url, besides: names) else { continue }
                guard !exclusions.excludes(url), !exclusions.holds(url) else { continue }
                guard artifactNames.insert(definition.name).inserted else { continue }
                matching.append(definition)
            }
            // Read after all of the project's artifacts are found, so the walk skips every one of them.
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

    /// A hidden folder is usually a tool's own store, such as `~/.npm` with its many `node_modules`, which belong
    /// to the Developer page. A generic name like `public` is walked, since it is the person's own folder unless
    /// the file of the tool that makes it sits beside it.
    static func isSkipped(_ name: String) -> Bool {
        if name.hasPrefix(".") || name == "Library" { return true }
        return definitions.contains { $0.name == name && !$0.isGeneric }
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

    /// Files Git updates whenever the repository changes: three reads can answer for a whole repository.
    private static let gitMarks = [".git/index", ".git/HEAD", ".git/logs/HEAD"]

    /// Stops at the first change within `recentlyActive`, which alone answers the question.
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

    /// A cache directory tag is how a tool says everything inside can be made again (Cache Directory Tagging
    /// Specification).
    static func isTaggedAsACache(_ folder: URL) -> Bool {
        let signature = Data("Signature: 8a477f597d28d172789f06886806bc55".utf8)
        guard let tag = BoundedRead.data(at: folder.appending(path: "CACHEDIR.TAG"), maximum: 4_096) else { return false }
        return tag.starts(with: signature)
    }

    /// Not a link, a cloud placeholder, or a package: an Electron app ships `package.json` beside `node_modules`
    /// inside its bundle.
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
    public func matches(_ query: String) -> Bool {
        guard !query.isEmpty else { return true }
        return SearchText.matches(name, query)
            || SearchText.matches(tool, query)
            || SearchText.matches(project.lastPathComponent, query)
    }
}
