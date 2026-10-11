public import Foundation
internal import PeelPrivileged

/// A folder a build or a package manager leaves inside a project. It counts only when the project file behind it
/// sits beside it (`package.json` for `node_modules`), so a `build` folder no tool made is left alone.
public struct ProjectArtifact: Sendable, Hashable, Identifiable {
    public let url: URL
    public let project: URL
    public let name: String
    /// Nil for a folder known only by the cache directory tag its tool wrote, which does not say which tool it was.
    public let tool: String?
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

extension Collection where Element == ProjectArtifact {
    public var selectableRows: SelectableRows<URL> {
        SelectableRows(
            rows: map(\.url), selectable: map(\.url), recommended: filter(\.isRecommended).map(\.url)
        )
    }
}

public enum ProjectArtifacts {
    /// A project changed within this time is in use, so none of its artifacts are selected for the user.
    public static let recentlyActive: TimeInterval = 7 * 24 * 60 * 60

    /// When a project's own files last changed, as far as its artifacts' walks could tell.
    public enum LastChange: Sendable, Equatable {
        /// Seen within `recentlyActive`, which is true however much of the project was read.
        case recently
        case at(Date)
        /// The project was too large to read whole, so the newest date seen is only a sample's.
        case notKnown
        case none
    }

    public static func lastChange(of artifacts: [ProjectArtifact]) -> LastChange {
        if artifacts.contains(where: \.isRecentlyActive) { return .recently }
        if artifacts.contains(where: { !$0.lastActivityIsCertain }) { return .notKnown }
        return artifacts.compactMap(\.lastActivity).max().map { .at($0) } ?? .none
    }

    /// The artifacts to leave out of Time Machine: never one with a generic name, since the mark travels with the
    /// folder, even into a copy of it (`man tmutil`), and never an environment, which holds what no build makes
    /// again (`.terraform` keeps the chosen workspace and the backend's settings).
    public static func markableForBackups(_ artifacts: [ProjectArtifact], excludedFromAbove: Set<URL>) -> [URL] {
        artifacts.filter { !$0.hasGenericName && !$0.isEnvironment && !excludedFromAbove.contains($0.url) }.map(\.url)
    }

    struct Definition: Sendable {
        let name: String
        /// A leading `*` matches any name with that ending, as in `*.xcodeproj`, and a path names a file inside a
        /// folder beside the artifact, as in `ProjectSettings/ProjectVersion.txt`.
        let markers: [String]
        let tool: String
        let isGeneric: Bool
        var isEnvironment = false
        /// Where the tool documents the folder: a page, or what Xcode itself prints.
        let source: String
        /// What the folder holds that only its tool writes, for a kind no project file stands beside.
        var proof: Proof?

        /// The artifacts this kind names among a folder's entries: a name ending in `*` is a prefix, as CLion names
        /// a build folder for each profile, and a path names a folder inside one of them, as Rails keeps `tmp/cache`.
        func candidates(among names: Set<String>) -> [String] {
            if name.hasSuffix("*") {
                let prefix = name.dropLast()
                return names.filter { $0.hasPrefix(prefix) && $0.count > prefix.count }.sorted()
            }
            guard let first = PathComponents.of(name).first, names.contains(first) else { return [] }
            return [name]
        }

        func matches(_ url: URL, in folder: URL, besides names: Set<String>) -> Bool {
            guard markers.isEmpty || hasMarker(besides: names, in: folder) else { return false }
            return proof?.holds(at: url) ?? true
        }

        private func hasMarker(besides names: Set<String>, in folder: URL) -> Bool {
            markers.contains { marker in
                if marker.hasPrefix("*") {
                    let suffix = marker.dropFirst()
                    return names.contains { $0.hasSuffix(suffix) && $0.count > suffix.count }
                }
                guard let first = PathComponents.of(marker).first, names.contains(first) else { return false }
                return first == marker || Proof.holds(marker).holds(at: folder)
            }
        }
    }

    enum Proof: Sendable {
        /// A file the tool always writes inside, as `venv` writes `pyvenv.cfg`.
        case holds(String)
        /// Nothing but files with this ending, as Python writes only compiled `.pyc` files into `__pycache__`.
        case holdsOnlyFilesEnding(String)
        /// Nothing but entries with these names, `including` among them.
        case holdsOnly(Set<String>, including: String)

        func holds(at url: URL) -> Bool {
            switch self {
            case .holds(let name):
                var info = stat()
                let path = url.appending(path: name).path(percentEncoded: false)
                return lstat(path, &info) == 0 && info.st_mode & S_IFMT == S_IFREG
            case .holdsOnly(let names, let including):
                let path = url.path(percentEncoded: false)
                let entries = Set((try? FileManager.default.contentsOfDirectory(atPath: path)) ?? [])
                return entries.contains(including) && entries.isSubset(of: names)
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
    private static let docusaurusConfigFiles = ["ts", "mts", "cts", "js", "mjs", "cjs"].map { "docusaurus.config." + $0 }
    private static let nycConfigFiles = [".nycrc", ".nycrc.json", ".nycrc.yaml", ".nycrc.yml"]
        + ["js", "cjs", "mjs"].map { "nyc.config." + $0 }
    private static let unityProjectFile = "ProjectSettings/ProjectVersion.txt"
    private static let dotNetProjectFiles = ["*.csproj", "*.fsproj", "*.vbproj", "*.sln"]
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
        // Only what `carthage build` makes: `Carthage/Checkouts` holds the dependencies' source, which people commit
        // in and, with `--use-submodules`, change.
        Definition(
            name: "Carthage/Build", markers: ["Cartfile"], tool: "Carthage", isGeneric: false,
            source: "https://github.com/Carthage/Carthage/blob/e33e133a5427129b38bfb1ae18d8f56b29a93204/Documentation/Artifacts.md"
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
            name: ".nyc_output", markers: ["package.json"] + nycConfigFiles, tool: "nyc", isGeneric: false,
            source: "https://github.com/istanbuljs/nyc/blob/908620475199fa7b9ea0ea8b21d6d8ad6921e3ae/README.md#L87-L113"
        ),
        Definition(
            name: ".docusaurus", markers: docusaurusConfigFiles, tool: "Docusaurus", isGeneric: false,
            source: "https://github.com/facebook/docusaurus/blob/c245217563f6491fdb79bf5ac91bfa16536e5de9/packages/docusaurus/src/commands/clear.ts#L33-L52"
        ),
        Definition(
            name: "build", markers: docusaurusConfigFiles, tool: "Docusaurus", isGeneric: true,
            source: "https://github.com/facebook/docusaurus/blob/c245217563f6491fdb79bf5ac91bfa16536e5de9/packages/docusaurus/src/commands/clear.ts#L33-L52"
        ),
        // Only what `nx reset` removes, the cache and the database together: before Nx's #37111 a database row whose
        // files were gone was a hit that restored nothing. `.nx` can also hold the release plans a team commits.
        Definition(
            name: ".nx", markers: ["nx.json"], tool: "Nx", isGeneric: false,
            source: "https://github.com/nrwl/nx/blob/ead04276f840b920ffab97eb3f809fef2baf130b/packages/nx/src/command-line/reset/reset.ts#L156-L205",
            proof: .holdsOnly(["cache", "workspace-data"], including: "workspace-data")
        ),
        Definition(
            name: ".parcel-cache", markers: ["package.json"], tool: "Parcel", isGeneric: false,
            source: "https://parceljs.org/features/cli/"
        ),
        Definition(
            name: "storybook-static", markers: [".storybook"], tool: "Storybook", isGeneric: false,
            source: "https://github.com/storybookjs/storybook/blob/dc9b30e8fd8a71383ec01b9510f38bee51457e8a/code/core/src/cli/build.ts"
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
            name: "target", markers: ["build.sbt"], tool: "sbt", isGeneric: true,
            source: "https://www.scala-sbt.org/1.x/docs/Directories.html"
        ),
        Definition(
            name: "project/target", markers: ["build.sbt"], tool: "sbt", isGeneric: true,
            source: "https://www.scala-sbt.org/1.x/docs/Directories.html"
        ),
        Definition(
            name: ".cpcache", markers: ["deps.edn"], tool: "Clojure CLI", isGeneric: false,
            source: "https://github.com/clojure/clojure-site/blob/15d0adc7ccd1dc8aa1c622dc824bef76507c276a/content/reference/clojure_cli.adoc#L490-L504"
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
        Definition(
            name: "Library", markers: [unityProjectFile], tool: "Unity", isGeneric: true,
            source: "https://docs.unity.com/en-us/unity-version-control/ignore-files"
        ),
        Definition(
            name: "Temp", markers: [unityProjectFile], tool: "Unity", isGeneric: true,
            source: "https://docs.unity.com/en-us/unity-version-control/ignore-files"
        ),
        Definition(
            name: "Logs", markers: [unityProjectFile], tool: "Unity", isGeneric: true,
            source: "https://docs.unity.com/en-us/unity-version-control/ignore-files"
        ),
        Definition(
            name: "obj", markers: [unityProjectFile], tool: "Unity", isGeneric: true,
            source: "https://docs.unity.com/en-us/unity-version-control/ignore-files"
        ),
        Definition(
            name: "Binaries", markers: ["*.uproject"], tool: "Unreal Engine", isGeneric: true,
            source: "https://dev.epicgames.com/documentation/en-us/unreal-engine/unreal-engine-directory-structure"
        ),
        Definition(
            name: "Intermediate", markers: ["*.uproject"], tool: "Unreal Engine", isGeneric: true,
            source: "https://dev.epicgames.com/documentation/en-us/unreal-engine/unreal-engine-directory-structure"
        ),
        Definition(
            name: "DerivedDataCache", markers: ["*.uproject"], tool: "Unreal Engine", isGeneric: false,
            source: "https://dev.epicgames.com/documentation/en-us/unreal-engine/unreal-engine-directory-structure"
        ),
        // `.godot` itself also holds the export passwords and keys (`export_credentials.cfg`), kept nowhere else.
        Definition(
            name: ".godot/imported", markers: ["project.godot"], tool: "Godot", isGeneric: false,
            source: "https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/import_process.html"
        ),
        Definition(
            name: ".godot/shader_cache", markers: ["project.godot"], tool: "Godot", isGeneric: false,
            source: "https://github.com/godotengine/godot/blob/232e6b14abf6e590b41d60f11704e42de22bff72/main/main.cpp#L2113-L2116"
        ),
        Definition(
            name: ".import", markers: ["project.godot"], tool: "Godot", isGeneric: false,
            source: "https://docs.godotengine.org/en/3.6/tutorials/best_practices/version_control_systems.html"
        ),
        Definition(
            name: "build", markers: ["CMakeLists.txt"], tool: "CMake", isGeneric: true,
            source: "https://cmake.org/cmake/help/latest/manual/cmake.1.html"
        ),
        Definition(
            name: "autom4te.cache", markers: ["configure.ac", "configure.in"], tool: "Autoconf", isGeneric: false,
            source: "https://www.gnu.org/software/autoconf/manual/autoconf-2.72/html_node/Autom4te-Cache.html"
        ),
        Definition(
            name: "cmake-build-*", markers: ["CMakeLists.txt"], tool: "CLion", isGeneric: false,
            source: "https://www.jetbrains.com/help/clion/quick-cmake-tutorial.html"
        ),
        Definition(
            name: "build", markers: ["*.xcodeproj"], tool: "Xcode", isGeneric: true,
            source: "Xcode 27: xcodebuild -showBuildSettings (SYMROOT, the project's build folder)"
        ),
        Definition(
            name: "zig-out", markers: ["build.zig"], tool: "Zig", isGeneric: false,
            source: "https://ziglang.org/learn/build-system/"
        ),
        Definition(
            name: ".zig-cache", markers: ["build.zig"], tool: "Zig", isGeneric: false,
            source: "https://ziglang.org/learn/build-system/"
        ),
        Definition(
            name: "zig-cache", markers: ["build.zig"], tool: "Zig", isGeneric: false,
            source: "https://ziglang.org/download/0.13.0/release-notes.html"
        ),
        Definition(
            name: ".cxx", markers: gradleFiles, tool: "Android Gradle plugin", isGeneric: false,
            source: "https://developer.android.com/studio/projects/gradle-external-native-builds"
        ),
        Definition(
            name: ".stack-work", markers: ["stack.yaml"], tool: "Stack", isGeneric: false,
            source: "https://docs.haskellstack.org/en/stable/topics/stack_work/"
        ),
        Definition(
            name: "dist-newstyle", markers: ["cabal.project", "*.cabal"], tool: "Cabal", isGeneric: false,
            source: "https://cabal.readthedocs.io/en/stable/nix-local-build.html"
        ),
        Definition(
            name: "_build", markers: ["mix.exs"], tool: "Mix", isGeneric: true,
            source: "https://mix.hexdocs.pm/Mix.Tasks.Clean.html"
        ),
        Definition(
            name: "deps", markers: ["mix.exs"], tool: "Mix", isGeneric: true, isEnvironment: true,
            source: "https://mix.hexdocs.pm/Mix.Tasks.Clean.html"
        ),
        Definition(
            name: ".elixir_ls", markers: ["mix.exs"], tool: "ElixirLS", isGeneric: false,
            source: "https://github.com/elixir-lsp/elixir-ls/blob/68df44b681ee0dbef91b8008b0354003a9a451fa/README.md"
        ),
        Definition(
            name: "lib", markers: ["shard.lock"], tool: "Shards", isGeneric: true, isEnvironment: true,
            source: "https://crystal-lang.org/reference/latest/man/shards/index.html"
        ),
        Definition(
            name: "vendor", markers: ["composer.json"], tool: "Composer", isGeneric: true, isEnvironment: true,
            source: "https://getcomposer.org/doc/01-basic-usage.md"
        ),
        Definition(
            name: "tmp/cache", markers: ["config/application.rb"], tool: "Rails", isGeneric: false,
            source: "https://guides.rubyonrails.org/command_line.html"
        ),
        Definition(
            name: ".terragrunt-cache", markers: ["terragrunt.hcl"], tool: "Terragrunt", isGeneric: false,
            source: "https://docs.terragrunt.com/features/units/terragrunt-cache/"
        ),
        // After the game engines, whose projects carry a .NET project file too.
        Definition(
            name: "bin", markers: dotNetProjectFiles, tool: ".NET", isGeneric: true,
            source: "https://learn.microsoft.com/en-us/dotnet/core/project-sdk/msbuild-props"
        ),
        Definition(
            name: "obj", markers: dotNetProjectFiles, tool: ".NET", isGeneric: true,
            source: "https://learn.microsoft.com/en-us/visualstudio/msbuild/common-msbuild-project-properties"
        ),
    ]

    /// Duplicates uses it to recognize a project folder and leave it alone.
    static func isMarker(_ name: String) -> Bool {
        exactMarkers.contains(name) || markerSuffixes.contains { name.hasSuffix($0) && name.count > $0.count }
    }

    private static let exactMarkers = Set(
        definitions.flatMap(\.markers).filter { !$0.hasPrefix("*") }.compactMap { PathComponents.of($0).first }
    )
    private static let markerSuffixes = Set(
        definitions.flatMap(\.markers).filter { $0.hasPrefix("*") }.map { String($0.dropFirst()) }
    )

    static let maximumDepth = 8
    static let maximumFolders = 40_000
    /// Past this many entries read, a project's last change counts as unknown.
    static let maximumActivitySamples = 2_000

    public struct Scan: Sendable {
        public var artifacts: [ProjectArtifact] = []
        /// True when the scan reached `maximumFolders` and left the deepest folders unread.
        public var wasCutShort = false
        /// The folders that are there and could not be read, or did not answer in time, so what they hold isn't known.
        public var unreadableLocations: [URL] = []
        /// True when macOS kept Peel out of one of them for want of Full Disk Access.
        public var needsFullDiskAccess = false
        /// The chosen folders that were not searched at all, each with the reason, in the order they were given.
        public var refusedRoots: [(url: URL, reason: Refusal)] = []
    }

    @concurrent
    public static func scan(roots: [URL], exclusions: Exclusions = .none) async -> Scan {
        await scan(roots: roots, exclusions: exclusions, measure: LeftoverScanner.walk)
    }

    @concurrent
    static func scan(roots: [URL], exclusions: Exclusions, measure: @escaping LeftoverScanner.Measure) async -> Scan {
        await withTaskGroup(of: (artifacts: [ProjectArtifact], wasCutShort: Bool, unreadable: [URL]).self) { group in
            var refused: [(url: URL, reason: Refusal)] = []
            for root in roots {
                if let reason = refusal(for: root) {
                    refused.append((root, reason))
                    continue
                }
                group.addTask { await artifacts(in: root, exclusions: exclusions, measure: measure) }
            }
            var found: [ProjectArtifact] = []
            var seen: Set<URL> = []
            var wasCutShort = false
            var unreadable: [URL] = []
            for await result in group {
                wasCutShort = wasCutShort || result.wasCutShort
                unreadable += result.unreadable
                for artifact in result.artifacts where seen.insert(artifact.url).inserted {
                    found.append(artifact)
                }
            }
            return Scan(
                artifacts: await holdingBackWhatGitTracks(found).sorted { SizeTotal([$0.size]) > SizeTotal([$1.size]) },
                wasCutShort: wasCutShort,
                unreadableLocations: unreadable.sorted {
                    PathPattern.comparablePath(of: $0) < PathPattern.comparablePath(of: $1)
                },
                needsFullDiskAccess: unreadable.contains { FullDiskAccess.canList($0) == .missing },
                refusedRoots: refused
            )
        }
    }

    /// Holds back each artifact Git tracks files in, which is part of the project rather than something a build makes
    /// again, and each in a repository whose index can't be read. What the walk saw inside comes first.
    static func holdingBackWhatGitTracks(_ artifacts: [ProjectArtifact]) async -> [ProjectArtifact] {
        var result = artifacts
        var indexes: [GitIndex.Repository: GitIndex?] = [:]
        let projects = Dictionary(grouping: result.indices.filter { result[$0].heldBack == nil }) { result[$0].project }
        for (project, positions) in projects {
            guard !Task.isCancelled else { break }
            func hold(_ reason: HoldBack, _ held: [Int]) {
                for position in held { result[position].heldBack = reason }
            }
            let found = await SlowRead.answer(within: FileSize.budget) { _ in GitIndex.repository(containing: project) }
            guard let found else {
                hold(.gitTrackingNotKnown, positions)
                continue
            }
            guard let repository = found else { continue }
            let index: GitIndex?
            if let read = indexes[repository] {
                index = read
            } else {
                index = await SlowRead.answer(within: FileSize.budget) { _ in GitIndex.read(repository) } ?? nil
                indexes.updateValue(index, forKey: repository)
            }
            guard let index else {
                hold(.gitTrackingNotKnown, positions)
                continue
            }
            let folders = positions.map { result[$0].url }
            let tracked = await SlowRead.answer(within: FileSize.budget) { _ in
                folders.map { index.tracksSomething(atOrInside: $0, of: repository) }
            }
            guard let tracked else {
                hold(.gitTrackingNotKnown, positions)
                continue
            }
            hold(.trackedByGit, zip(positions, tracked).filter(\.1).map(\.0))
        }
        return result
    }

    public enum Refusal: Sendable, Hashable {
        case tooBroad
        case inTheCloud
        case notAFolder
        /// An app or another package, or a folder inside one: what is inside belongs to it.
        case inAPackage
        /// A folder the walk never enters (`isSkipped`), or one inside it: apps and tools keep what they install there.
        case neverSearched
    }

    /// The folders in the home folder where people usually keep projects, suggested until one is chosen: each is
    /// offered only when it is a real folder there, never a link, and the person still confirms it.
    public static func suggestedRoots(home: URL = .homeDirectory) -> [URL] {
        ["Developer", "Projects", "Code", "src"].compactMap { name in
            let url = home.appending(path: name, directoryHint: .isDirectory)
            return url.isRealFolder && refusal(for: url, home: home) == nil ? url : nil
        }
    }

    /// Why `root` cannot be searched, or nil. Every spelling of the path is checked: `/users/me` and
    /// `/System/Volumes/Data/Users/me` are the same home folder, and a link into a cloud folder is that cloud folder.
    public static func refusal(for root: URL, home: URL = .homeDirectory) -> Refusal? {
        let spellings = ([PathPattern.comparablePath(of: root), PathPattern.canonical(root).path(percentEncoded: false)]
            + Array(ProtectedData.spellings(of: PathPattern.comparablePath(of: root)))).map { $0.lowercased() }
        let homes = ([PathPattern.comparablePath(of: home), PathPattern.canonical(home).path(percentEncoded: false)]
            + Array(ProtectedData.spellings(of: PathPattern.comparablePath(of: home)))).map { spelling in
                var path = spelling.lowercased()
                while path.count > 1, path.hasSuffix("/") { path.removeLast() }
                return path
            }

        for spelling in spellings {
            var path = spelling
            while path.count > 1, path.hasSuffix("/") { path.removeLast() }
            let components = PathComponents.of(path)
            let isInACloudFolder = zip(components, components.dropFirst()).contains { folder, inside in
                folder == "library" && ["mobile documents", "cloudstorage"].contains(inside)
            }
            if isInACloudFolder { return .inTheCloud }
            // A home folder and a volume root both have two components, so they are recognized by name.
            if components.count < 2 || homes.contains(path) { return .tooBroad }
            if components.count == 2, ["users", "volumes"].contains(components[0]) { return .tooBroad }
            if path == "/system/volumes/data" { return .tooBroad }
            if components.count == 5, components.starts(with: ["system", "volumes", "data", "users"]) { return .tooBroad }
        }

        var isDirectory: ObjCBool = false
        let isThere =
            FileManager.default.fileExists(atPath: PathPattern.comparablePath(of: root), isDirectory: &isDirectory)
            && isDirectory.boolValue
        guard isThere else { return .notAFolder }
        if root.isOrIsInsideAPackage { return .inAPackage }
        // The kernel's name for the folder: links resolved, each name as the disk holds it, as the walk sees names.
        let names = PathComponents.of(PathPattern.canonical(root).path(percentEncoded: false))
        return names.contains(where: isSkipped) ? .neverSearched : nil
    }

    /// Walks `root` for artifacts. Each folder is read on a thread of its own, within `FileSize`'s budget, since a
    /// folder on a network volume that stopped answering would otherwise hold one of the threads every scan
    /// shares, where a Stop cannot reach it. `listing` stands in for the listing in a test.
    static func artifacts(
        in root: URL,
        exclusions: Exclusions,
        measure: LeftoverScanner.Measure,
        listing: @escaping @Sendable (URL) -> [URL]? = contents(of:)
    ) async -> (artifacts: [ProjectArtifact], wasCutShort: Bool, unreadable: [URL]) {
        var found: [ProjectArtifact] = []
        var unreadable: [URL] = []
        var queue: [(url: URL, depth: Int)] = [(root, 0)]
        // An index, since `removeFirst` would make the walk quadratic.
        var next = 0
        var visited = 0
        var reached: Set<String> = []

        while next < queue.count, visited < maximumFolders, !Task.isCancelled {
            let (folder, depth) = queue[next]
            next += 1
            visited += 1
            // The folders already walked are let go now and then, so a long walk does not keep them all.
            if next >= 4_096 {
                queue.removeFirst(next)
                next = 0
            }
            let answer = await SlowRead.answer(within: FileSize.budget) { _ in
                look(in: folder, exclusions: exclusions, listing: listing)
            }
            // A folder that went away during the walk held nothing; one still there and not read is not known.
            guard let look = answer ?? nil else {
                if !folder.isMissing { unreadable.append(folder) }
                continue
            }
            ScanCount.current?.add(look.entries.count)
            let artifactNames = Set(look.found.map(\.name))
            for artifact in look.found {
                reached.insert(Self.key(of: folder.appending(path: artifact.name)))
            }

            // Read after all of the project's artifacts are found, so the walk skips every one of them.
            let activity = look.found.isEmpty
                ? (date: nil, isCertain: true)
                : await SlowRead.answer(within: FileSize.budget) { isGivenUp in
                    lastActivity(in: folder, ignoring: artifactNames, isGivenUp: isGivenUp)
                } ?? (date: nil, isCertain: false)
            for artifact in look.found {
                let url = folder.appending(path: artifact.name)
                let contents = await measure(url)
                let heldBack = HoldBack.seen(in: contents)
                found.append(ProjectArtifact(
                    url: url,
                    project: folder,
                    name: artifact.name,
                    tool: artifact.definition?.tool,
                    size: contents.flatMap { $0.couldNotBeRead ? nil : $0.size },
                    lastActivity: activity.date,
                    lastActivityIsCertain: activity.isCertain,
                    hasGenericName: artifact.definition?.isGeneric ?? false,
                    isEnvironment: artifact.definition?.isEnvironment ?? false,
                    // A tool that tags its folder as a cache makes everything in it again, its own clones included.
                    heldBack: heldBack == .holdsRepository && artifact.isTaggedAsACache ? nil : heldBack
                ))
            }

            guard depth < maximumDepth else { continue }
            for entry in look.entries where !reached.contains(Self.key(of: entry)) {
                guard isRealFolder(entry), !exclusions.excludes(entry), !isSkipped(entry.lastPathComponent) else {
                    continue
                }
                queue.append((entry, depth + 1))
            }
        }
        return (found, next < queue.count, unreadable)
    }

    /// What one folder holds and which of its entries are artifacts.
    private struct Look: Sendable {
        let entries: [URL]
        let found: [Found]
    }

    private struct Found: Sendable {
        let name: String
        let definition: Definition?
        let isTaggedAsACache: Bool
    }

    /// Lists `folder` and finds the artifacts in it, or nil when it cannot be listed.
    private static func look(in folder: URL, exclusions: Exclusions, listing: (URL) -> [URL]?) -> Look? {
        guard let entries = listing(folder) else { return nil }
        let names = Set(entries.map(\.lastPathComponent))
        var artifactNames: Set<String> = []
        var found: [Found] = []
        for definition in definitions {
            for name in definition.candidates(among: names) {
                let url = folder.appending(path: name)
                guard isRealFolder(url), definition.matches(url, in: folder, besides: names) else { continue }
                guard !exclusions.excludes(url), !exclusions.holds(url) else { continue }
                guard artifactNames.insert(name).inserted else { continue }
                found.append(Found(name: name, definition: definition, isTaggedAsACache: isTaggedAsACache(url)))
            }
        }
        for entry in entries where !artifactNames.contains(entry.lastPathComponent) {
            guard isRealFolder(entry), isTaggedAsACache(entry) else { continue }
            guard !exclusions.excludes(entry), !exclusions.holds(entry) else { continue }
            artifactNames.insert(entry.lastPathComponent)
            found.append(Found(name: entry.lastPathComponent, definition: nil, isTaggedAsACache: true))
        }
        return Look(entries: entries, found: found)
    }

    /// A hidden folder is usually a tool's own store, such as `~/.npm` with its many `node_modules`, which belong
    /// to the Developer page. A generic name like `public` is walked, since it is the person's own folder unless
    /// the file of the tool that makes it sits beside it.
    static func isSkipped(_ name: String) -> Bool {
        if name.hasPrefix(".") || name == "Library" { return true }
        return definitions.contains { $0.name == name && !$0.isGeneric }
    }

    /// Files Git updates whenever the repository changes: three reads can answer for a whole repository.
    private static let gitMarks = [".git/index", ".git/HEAD", ".git/logs/HEAD"]

    /// What the read of a project's last change passes by besides its artifacts: Git's own store, which its marks
    /// answer for, and installed packages, which change when they are installed rather than when anyone works.
    private static let passedByForActivity: Set<String> = [".git", "node_modules"]

    /// Stops at the first change within `recentlyActive`, which alone answers the question.
    static func lastActivity(
        in project: URL,
        ignoring artifacts: Set<String>,
        isGivenUp: () -> Bool = { false }
    ) -> (date: Date?, isCertain: Bool) {
        let cutoff = Date.now.addingTimeInterval(-recentlyActive)
        var newest: Date?
        for mark in gitMarks {
            let url = project.appending(path: mark)
            guard let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            else { continue }
            if newest == nil || date > newest! { newest = date }
            if date > cutoff { return (date, true) }
        }

        guard let enumerator = FileManager.default.enumerator(
            at: project,
            includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
            options: [.skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else { return (newest, newest != nil) }

        let base = key(of: project)
        var samples = 0
        for case let url as URL in enumerator {
            guard !isGivenUp() else { return (newest, false) }
            let name = url.lastPathComponent
            let relative = String(key(of: url).dropFirst(base.count + 1))
            if artifacts.contains(name) || artifacts.contains(relative) || passedByForActivity.contains(name) {
                enumerator.skipDescendants()
                continue
            }
            samples += 1
            guard samples <= maximumActivitySamples else { return (newest, false) }
            guard let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            else { continue }
            if newest == nil || date > newest! { newest = date }
            if date > cutoff { return (date, true) }
        }
        return (newest, newest != nil)
    }

    static func key(of url: URL) -> String {
        var path = url.standardizedFileURL.path(percentEncoded: false)
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        return path
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
        let values = try? url.resourceValues(forKeys: [
            .isDirectoryKey, .isSymbolicLinkKey, .isUbiquitousItemKey, .isPackageKey,
        ])
        guard values?.isDirectory == true, values?.isSymbolicLink != true, values?.isPackage != true else {
            return false
        }
        return values?.isUbiquitousItem != true
    }

    static func contents(of folder: URL) -> [URL]? {
        try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isUbiquitousItemKey, .isPackageKey],
            options: []
        )
    }
}

extension ProjectArtifact {
    public func matches(_ query: String) -> Bool {
        guard !query.isEmpty else { return true }
        return SearchText.matches(name, query)
            || (tool.map { SearchText.matches($0, query) } ?? false)
            || SearchText.matches(project.lastPathComponent, query)
    }
}
