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

    public enum Kept: Sendable, Equatable {
        case heldBack(HoldBack)
        case installedPackages
        case genericName
        case changedRecently
        case lastChangeNotKnown
    }

    /// Why Peel doesn't suggest it, or nil when it does. What time doesn't change comes first, so a folder that will
    /// never be suggested on its own doesn't read as one that only has to wait.
    public var keptBecause: Kept? {
        if let heldBack { return .heldBack(heldBack) }
        if isEnvironment { return .installedPackages }
        if hasGenericName { return .genericName }
        if isRecentlyActive { return .changedRecently }
        if !lastActivityIsCertain { return .lastChangeNotKnown }
        return nil
    }

    public var isRecommended: Bool { keptBecause == nil }
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

    public struct BackupMarks: Sendable, Equatable {
        /// What turning the Time Machine switch on leaves out of backups: never a folder with a generic name, since the
        /// mark travels with the folder, even into a copy of it (`man tmutil`), never an environment, which holds what
        /// no build makes again (`.terraform` keeps the chosen workspace and the backend's settings), and never one
        /// held back, whose hold back says a build does not make all of it again.
        public let markable: [URL]
        /// The folders carrying Peel's own mark, which turning the switch off takes away.
        public let marked: [URL]
        /// The folders whose own mark is another's: Peel never marks a folder with a generic name, so a mark on one is
        /// its tool's, as Cargo marks `target`, or the person's. The switch neither shows it nor takes it away.
        public let markedByOthers: [URL]
        private let shown: [URL]
        private let excluded: Set<URL>

        /// `excludedFromAbove`: what Time Machine leaves out through a folder above or a rule of its own, not Peel's.
        public init(_ artifacts: [ProjectArtifact], excluded: Set<URL>, excludedFromAbove: Set<URL>) {
            let considered = artifacts.filter { !$0.hasGenericName && !$0.isEnvironment && $0.heldBack == nil }
                .map(\.url)
            let markedItself = { (artifact: ProjectArtifact) in
                excluded.contains(artifact.url) && !excludedFromAbove.contains(artifact.url)
            }
            markable = considered.filter { !excludedFromAbove.contains($0) }
            marked = artifacts.filter { markedItself($0) && !$0.hasGenericName }.map(\.url)
            markedByOthers = artifacts.filter { markedItself($0) && $0.hasGenericName }.map(\.url)
            shown = considered + marked.filter { !considered.contains($0) }
            self.excluded = excluded
        }

        /// On while everything the switch is about is left out of backups, what Peel marked before included.
        public var isOn: Bool { !shown.isEmpty && shown.allSatisfy(excluded.contains) }
        public var canChange: Bool { !markable.isEmpty || !marked.isEmpty }

        public func folders(turning isOn: Bool) -> [URL] { isOn ? markable : marked }
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
        var keepsItsSetup = false
        var isFoundOnlyByItsTag = false
        /// The tool clones its dependencies inside and clones them again, so a repository there is not the person's.
        var remakesItsClones = false

        /// Names ending in `*` are prefixes, and a path such as `tmp/cache` names a folder inside another.
        func candidates(among names: Set<String>, in folder: URL) -> [String] {
            let parts = PathComponents.of(name)
            guard let first = parts.first, let last = parts.last else { return [] }
            guard last.hasSuffix("*") else { return names.contains(first) ? [name] : [] }
            let above = parts.dropLast().joined(separator: "/")
            guard above.isEmpty || names.contains(first) else { return [] }
            let entries = above.isEmpty
                ? Array(names) : ProjectArtifacts.contents(of: folder.appending(path: above))?.map(\.lastPathComponent)
            let prefix = last.dropLast()
            return (entries ?? []).filter { $0.hasPrefix(prefix) && $0.count > prefix.count }
                .map { above.isEmpty ? $0 : "\(above)/\($0)" }.sorted()
        }

        /// Whether a file of the tool stands in `folder`, or the kind needs none.
        func hasMarker(besides names: Set<String>, in folder: URL) -> Bool {
            markers.isEmpty || markers.contains { marker in
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
        /// Only folders named by a lowercase hexadecimal digest of this length, as Ruby Sass names its cache's.
        case holdsOnlyFoldersNamedByDigest(characters: Int)

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
            case .holdsOnlyFoldersNamedByDigest(let characters):
                let entries = ProjectArtifacts.contents(of: url) ?? []
                return !entries.isEmpty && entries.allSatisfy { entry in
                    let name = entry.lastPathComponent.utf8
                    return name.count == characters && name.allSatisfy { "0123456789abcdef".utf8.contains($0) }
                        && ProjectArtifacts.isRealFolder(entry)
                }
            }
        }
    }

    private static let gradleFiles = ["build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts"]
    private static let pythonProjectFiles = ["pyproject.toml", "requirements.txt", "Pipfile", "setup.py"]
    private static let nextConfigFiles = ["next.config.js", "next.config.mjs", "next.config.ts"]
    private static let samProjectFiles = ["template.yaml", "template.yml", "samconfig.toml"]
    private static let nuxtConfigFiles = ["nuxt.config.ts", "nuxt.config.js", "nuxt.config.mjs"]
    private static let astroConfigFiles = ["mjs", "js", "cjs", "ts", "mts", "cts"].map { "astro.config." + $0 }
    private static let expoConfigFiles = ["app.json", "app.config.js", "app.config.ts"]
    private static let viteConfigFiles = ["ts", "mts", "cts", "js", "mjs", "cjs"].map { "vite.config." + $0 }
    private static let vitestConfigFiles = ["ts", "mts", "cts", "js", "mjs", "cjs"].map { "vitest.config." + $0 }
    private static let gatsbyConfigFiles = ["gatsby-config.js", "gatsby-config.ts", "gatsby-config.mjs"]
    private static let jekyllConfigFiles = ["_config.yml", "_config.yaml", "_config.toml"]
    private static let quartoProjectFiles = ["_quarto.yml", "_quarto.yaml"]
    private static let eleventyConfigFiles = [".eleventy.js"] + ["buildawesome.config", "eleventy.config"].flatMap { name in
        ["js", "mjs", "cjs", "ts", "mts", "cts"].map { "\(name).\($0)" }
    }
    private static let docusaurusConfigFiles = ["ts", "mts", "cts", "js", "mjs", "cjs"].map { "docusaurus.config." + $0 }
    private static let nycConfigFiles = [".nycrc", ".nycrc.json", ".nycrc.yaml", ".nycrc.yml"]
        + ["js", "cjs", "mjs"].map { "nyc.config." + $0 }
    private static let serverlessFiles = ["yml", "yaml", "json", "js", "mjs", "cjs", "ts"].map { "serverless." + $0 }
    private static let reactRouterConfigFiles = ["js", "jsx", "ts", "tsx", "mjs", "mts"].map { "react-router.config." + $0 }
    private static let remixConfigFiles = ["js", "cjs", "mjs"].map { "remix.config." + $0 }
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
            source: "Xcode 27: swift build --help (--scratch-path, default .build)", remakesItsClones: true
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
        // `.astro` also holds `settings.json`, the preferences set with `astro preferences`, kept nowhere else.
        Definition(
            name: ".astro", markers: astroConfigFiles, tool: "Astro", isGeneric: false,
            source: "https://github.com/withastro/astro/blob/0a1036eef62f13c9609362874c5b88434d1e9300/packages/astro/src/preferences/README.md",
            keepsItsSetup: true
        ),
        Definition(
            name: ".expo", markers: expoConfigFiles, tool: "Expo", isGeneric: false,
            source: "https://github.com/expo/expo/blob/119b336f677fc6ce44658ea34f79ba823028923d/packages/@expo/cli/src/start/project/dotExpo.ts#L56-L69"
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
            name: ".rollup.cache", markers: ["package.json"], tool: "@rollup/plugin-typescript", isGeneric: false,
            source: "https://github.com/rollup/plugins/blob/639f45638234c1c3fabfb13615c78bebaef89ef2/packages/typescript/README.md#L289-L296"
        ),
        Definition(
            name: ".rpt2_cache", markers: ["package.json"], tool: "rollup-plugin-typescript2", isGeneric: false,
            source: "https://github.com/ezolenko/rollup-plugin-typescript2/blob/afaf7140fd640beb6164084a8f27f49e5f9b727e/src/index.ts#L52"
        ),
        Definition(
            name: ".vite-ssg-temp", markers: ["package.json"], tool: "Vite SSG", isGeneric: false,
            source: "https://github.com/antfu-collective/vite-ssg/blob/4be6e3c31b905f991cda89bcfd598442f8388ffd/src/node/build.ts#L38-L64"
        ),
        Definition(
            name: ".solid", markers: ["package.json"], tool: "SolidStart", isGeneric: false,
            source: "https://github.com/solidjs/solid-start/blob/2f44d456e4814b997058fb366d7361f0d6b1e4e8/packages/start-static/index.js#L28-L30"
        ),
        Definition(
            name: ".solid-start", markers: ["package.json"], tool: "SolidStart", isGeneric: false,
            source: "https://github.com/solidjs/solid-start/blob/9b943dc4a168e45bdce94dedc8a7ff54d402b4e8/packages/start/src/config/manifest.ts#L84"
        ),
        Definition(
            name: ".swc", markers: ["package.json", ".swcrc"], tool: "SWC", isGeneric: false,
            source: "https://github.com/swc-project/website/blob/81b00b1c8cc95477b64efd7f3f7a366a787757bd/apps/website/docs/docs/configuration/compilation.mdx#L671-L675"
        ),
        // Only the two bundles: `.shopify` also holds the app's local certificate and key, and its logs.
        Definition(
            name: ".shopify/deploy-bundle", markers: ["shopify.app.toml"], tool: "Shopify CLI", isGeneric: false,
            source: "https://github.com/Shopify/cli/blob/a9f536b4c023c89a9153dab0e31f899203443f5a/packages/app/src/cli/services/deploy/bundle.ts#L24-L26"
        ),
        Definition(
            name: ".shopify/dev-bundle", markers: ["shopify.app.toml"], tool: "Shopify CLI", isGeneric: false,
            source: "https://github.com/Shopify/cli/blob/a9f536b4c023c89a9153dab0e31f899203443f5a/packages/app/src/cli/services/dev/app-events/app-event-watcher.ts#L105"
        ),
        Definition(
            name: ".cache", markers: remixConfigFiles, tool: "Remix", isGeneric: true,
            source: "https://github.com/remix-run/remix/blob/5ff6f9a17add06e7f70da48480c1911ad0a1310f/docs/file-conventions/remix-config.md#L70-L73"
        ),
        Definition(
            name: "public/build", markers: remixConfigFiles, tool: "Remix", isGeneric: true,
            source: "https://github.com/remix-run/remix/blob/5ff6f9a17add06e7f70da48480c1911ad0a1310f/docs/file-conventions/remix-config.md#L44-L47"
        ),
        Definition(
            name: "build", markers: remixConfigFiles, tool: "Remix", isGeneric: true,
            source: "https://github.com/remix-run/remix/blob/5ff6f9a17add06e7f70da48480c1911ad0a1310f/docs/file-conventions/remix-config.md#L151-L155"
        ),
        Definition(
            name: "build", markers: reactRouterConfigFiles, tool: "React Router", isGeneric: true,
            source: "https://github.com/remix-run/react-router/blob/dee9ad2dab41889e8fbdc6848b5781255d9f133a/packages/react-router-dev/config/config.ts#L548"
        ),
        Definition(
            name: ".react-router", markers: ["package.json"] + reactRouterConfigFiles, tool: "React Router",
            isGeneric: false,
            source: "https://github.com/remix-run/react-router/blob/dee9ad2dab41889e8fbdc6848b5781255d9f133a/docs/how-to/route-module-type-safety.md#L17-L22"
        ),
        Definition(
            name: ".serverless", markers: serverlessFiles, tool: "Serverless Framework", isGeneric: false,
            source: "https://github.com/serverless/serverless/blob/de91219a8c8f28e07c308b2efc5187fae5445208/docs/sf/providers/aws/cli-reference/package.md#L16"
        ),
        // `.trigger` also keeps the dev session's state, so only its builds are offered.
        Definition(
            name: ".trigger/tmp", markers: ["trigger.config.ts", "trigger.config.mjs", "trigger.config.js"],
            tool: "Trigger.dev", isGeneric: false,
            source: "https://github.com/triggerdotdev/trigger.dev/blob/93465d8549a735074d1ce7696bae3faebe577e8d/packages/cli-v3/src/utilities/tempDirectories.ts#L6-L74"
        ),
        Definition(
            name: ".trigger/tmp-*", markers: ["trigger.config.ts", "trigger.config.mjs", "trigger.config.js"],
            tool: "Trigger.dev", isGeneric: false,
            source: "https://github.com/triggerdotdev/trigger.dev/blob/93465d8549a735074d1ce7696bae3faebe577e8d/packages/cli-v3/src/utilities/tempDirectories.ts#L6-L18"
        ),
        // `.vercel` also names the linked project and keeps the variables `vercel pull` wrote.
        Definition(
            name: ".vercel/output", markers: [".vercel/project.json", "vercel.json"], tool: "Vercel", isGeneric: false,
            source: "https://github.com/vercel/vercel/blob/c628be7835e03a965b93e9cf9e2bd5ac2acbf5eb/packages/cli/src/commands/build/index.ts#L366-L383"
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
        // Ruby Sass leaves its cache in whatever folder it ran from, so it is known by what it holds.
        Definition(
            name: ".sass-cache", markers: [], tool: "Ruby Sass", isGeneric: false,
            source: "https://github.com/sass/ruby-sass/blob/7a50eae567260a23d3bbf4d5aaf1a76db43dec32/lib/sass/engine.rb#L171",
            proof: .holdsOnlyFoldersNamedByDigest(characters: 40)
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
            name: ".cache", markers: eleventyConfigFiles, tool: "Eleventy Fetch", isGeneric: true,
            source: "https://github.com/11ty/eleventy-fetch/blob/b8e94a79cf3a950dd89d35a85e3e9586ed4fefe5/eleventy-fetch.js#L8-L11"
        ),
        Definition(
            name: "public", markers: gatsbyConfigFiles, tool: "Gatsby", isGeneric: true,
            source: "https://www.gatsbyjs.com/docs/reference/gatsby-cli/"
        ),
        Definition(
            name: "_site", markers: eleventyConfigFiles, tool: "Eleventy", isGeneric: true,
            source: "https://github.com/11ty/eleventy/blob/c0bb3f4219e00629f4f58a771c1783c898b9bdab/src/Util/ProjectDirectories.js#L10-L15"
        ),
        // `_site` is a generic name, and Jekyll keeps in it whatever its `keep_files` setting names.
        Definition(
            name: "_site", markers: jekyllConfigFiles, tool: "Jekyll", isGeneric: true,
            source: "https://github.com/jekyll/jekyll/blob/541d8b2ee75c8907de4744d4b87a7a6f1f997cae/lib/jekyll/configuration.rb#L9-L12"
        ),
        Definition(
            name: ".jekyll-cache", markers: jekyllConfigFiles, tool: "Jekyll", isGeneric: false,
            source: "https://github.com/jekyll/jekyll/blob/541d8b2ee75c8907de4744d4b87a7a6f1f997cae/lib/jekyll/commands/clean.rb#L20-L31"
        ),
        // `_freeze` holds results a project keeps in version control, so it is never listed.
        Definition(
            name: ".quarto", markers: quartoProjectFiles, tool: "Quarto", isGeneric: false,
            source: "https://github.com/quarto-dev/quarto-cli/blob/a57cc76458d91a0577c162a474929119e6b663ba/src/project/project-scratch.ts#L12-L24"
        ),
        Definition(
            name: "_site", markers: quartoProjectFiles, tool: "Quarto", isGeneric: true,
            source: "https://github.com/quarto-dev/quarto-cli/blob/a57cc76458d91a0577c162a474929119e6b663ba/src/project/types/website/website.ts#L112"
        ),
        Definition(
            name: "_book", markers: quartoProjectFiles, tool: "Quarto", isGeneric: true,
            source: "https://github.com/quarto-dev/quarto-cli/blob/a57cc76458d91a0577c162a474929119e6b663ba/src/project/types/book/book.ts#L115"
        ),
        Definition(
            name: "_site", markers: ["site.hs"], tool: "Hakyll", isGeneric: true,
            source: "https://github.com/jaspervdj/hakyll/blob/092b6a497326ba7b80d17249b6bbd41ca9bf5e19/lib/Hakyll/Core/Configuration.hs#L109-L111"
        ),
        Definition(
            name: "_cache", markers: ["site.hs"], tool: "Hakyll", isGeneric: true,
            source: "https://github.com/jaspervdj/hakyll/blob/092b6a497326ba7b80d17249b6bbd41ca9bf5e19/lib/Hakyll/Core/Configuration.hs#L109-L111"
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
        // xwin's downloads and, by default, the Windows SDK and CRT it unpacks for the build, which only `xwin splat`
        // with the person's own options puts back.
        Definition(
            name: ".xwin-cache", markers: ["Cargo.toml"], tool: "xwin", isGeneric: false, isEnvironment: true,
            source: "https://github.com/Jake-Shadle/xwin/blob/723d758d484f505c214e1b8c298fe34b19ba9e92/README.md#L42"
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
        // `.bloop` also keeps `bloop.settings.json`, the workspace settings written there.
        Definition(
            name: ".bloop", markers: ["build.sbt", "build.sc", "build.mill", "pom.xml"] + gradleFiles, tool: "Bloop",
            isGeneric: false,
            source: "https://github.com/scalacenter/bloop/blob/7d07f8224a2c5519c85e37edfef0ce4f42d4d4e6/docs/build-tools/sbt.md#L32-L37",
            keepsItsSetup: true
        ),
        Definition(
            name: "out", markers: ["build.mill", "build.mill.yaml", "build.sc"], tool: "Mill", isGeneric: true,
            source: "https://github.com/com-lihaoyi/mill/blob/454a2141b7f6baadaaa0dc3e85580221df675220/example/fundamentals/out-dir/1-out-files/build.mill#L1-L35"
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
            name: "ios/Flutter/ephemeral", markers: ["pubspec.yaml"], tool: "Flutter", isGeneric: false,
            source: "https://github.com/flutter/flutter/blob/3d9c69bf9efd3b4ac086629657003b47a0fde2f0/packages/flutter_tools/lib/src/xcode_project.dart#L162-L170"
        ),
        Definition(
            name: "macos/Flutter/ephemeral", markers: ["pubspec.yaml"], tool: "Flutter", isGeneric: false,
            source: "https://github.com/flutter/flutter/blob/3d9c69bf9efd3b4ac086629657003b47a0fde2f0/packages/flutter_tools/lib/src/xcode_project.dart#L162-L170"
        ),
        Definition(
            name: "linux/flutter/ephemeral", markers: ["pubspec.yaml"], tool: "Flutter", isGeneric: false,
            source: "https://github.com/flutter/flutter/blob/3d9c69bf9efd3b4ac086629657003b47a0fde2f0/packages/flutter_tools/lib/src/cmake_project.dart#L114-L121"
        ),
        Definition(
            name: "windows/flutter/ephemeral", markers: ["pubspec.yaml"], tool: "Flutter", isGeneric: false,
            source: "https://github.com/flutter/flutter/blob/3d9c69bf9efd3b4ac086629657003b47a0fde2f0/packages/flutter_tools/lib/src/cmake_project.dart#L80-L87"
        ),
        // A module's host apps, which Flutter writes again from its templates; editable ones are `ios` and `android`.
        Definition(
            name: ".ios", markers: ["pubspec.yaml"], tool: "Flutter", isGeneric: false,
            source: "https://github.com/flutter/flutter/blob/3d9c69bf9efd3b4ac086629657003b47a0fde2f0/packages/flutter_tools/lib/src/xcode_project.dart#L1092-L1125"
        ),
        Definition(
            name: ".android", markers: ["pubspec.yaml"], tool: "Flutter", isGeneric: false,
            source: "https://github.com/flutter/flutter/blob/3d9c69bf9efd3b4ac086629657003b47a0fde2f0/packages/flutter_tools/lib/src/project.dart#L1109-L1156"
        ),
        Definition(
            name: ".venv", markers: pythonProjectFiles, tool: "Python", isGeneric: false, isEnvironment: true,
            source: "https://docs.python.org/3/library/venv.html"
        ),
        Definition(
            name: "venv", markers: pythonProjectFiles, tool: "Python", isGeneric: false, isEnvironment: true,
            source: "https://docs.python.org/3/library/venv.html"
        ),
        // PDM installs a project's packages here, and the folder alone switches PDM to this mode.
        Definition(
            name: "__pypackages__", markers: pythonProjectFiles, tool: "PDM", isGeneric: false, isEnvironment: true,
            source: "https://github.com/pdm-project/pdm/blob/b5b69f414480b6974b8ab994b69b57bab91c0358/docs/usage/pep582.md#L7-L11"
        ),
        Definition(
            name: "env", markers: pythonProjectFiles, tool: "Python", isGeneric: true, isEnvironment: true,
            source: "https://docs.python.org/3/library/venv.html", proof: .holds("pyvenv.cfg")
        ),
        // uv and virtualenv tag every environment they make as a cache, whatever it is called.
        Definition(
            name: "*", markers: [], tool: "Python", isGeneric: false, isEnvironment: true,
            source: "https://peps.python.org/pep-0405/", proof: .holds("pyvenv.cfg"), isFoundOnlyByItsTag: true
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
            name: ".pyre", markers: [".pyre_configuration", "pyproject.toml"], tool: "Pyre", isGeneric: false,
            source: "https://github.com/facebook/pyre-check/blob/d5614e0a75f539443225fce3c3c55a77cfbfb72c/client/find_directories.py#L27-L32"
        ),
        Definition(
            name: ".pytype", markers: ["setup.cfg"] + pythonProjectFiles, tool: "pytype", isGeneric: false,
            source: "https://github.com/google/pytype/blob/f411a8b445c19500a737ba1671f071e001072618/pytype/tools/analyze_project/config.py#L65-L66"
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
        // Pixi makes these again from `pixi.lock` and never lets them be edited by hand; `.pixi` also holds the
        // project's own `config.toml`.
        Definition(
            name: ".pixi/envs", markers: ["pixi.toml", "pyproject.toml"], tool: "Pixi", isGeneric: false,
            source: "https://github.com/prefix-dev/pixi/blob/98535e0857e25ddc89457ef4779be2a961d8c2df/docs/workspace/environment.md#L70-L141"
        ),
        Definition(
            name: ".pants.d", markers: ["pants.toml"], tool: "Pants", isGeneric: false, source: "https://github.com/pantsbuild/pants/blob/5ec37d43741c80b9e7e999a51ef12cc3e6f3a6c8/docs/docs/using-pants/troubleshooting-common-issues.mdx#L153-L167"
        ),
        Definition(
            name: "dist", markers: ["pants.toml"], tool: "Pants", isGeneric: true, source: "https://github.com/pantsbuild/pants/blob/5ec37d43741c80b9e7e999a51ef12cc3e6f3a6c8/docs/docs/using-pants/troubleshooting-common-issues.mdx#L153-L167"
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
            name: ".liquid", markers: ["*.hs", "*.lhs"], tool: "LiquidHaskell", isGeneric: false,
            source: "https://github.com/ucsd-progsys/liquid-fixpoint/blob/684d0829c19fbee83b892c9f5e20c2598897297c/src/Language/Fixpoint/Utils/Files.hs#L146-L158"
        ),
        // Elm 0.18 keeps the project's packages there, and the exact versions it solved, which nothing else holds.
        Definition(
            name: "elm-stuff", markers: ["elm-package.json"], tool: "Elm", isGeneric: false, isEnvironment: true,
            source: "https://github.com/elm-lang/elm-package/blob/2076638d812d9dea641e6e695951495f523bb98f/src/Elm/Package/Paths.hs#L8-L45"
        ),
        Definition(
            name: "elm-stuff", markers: ["elm.json"], tool: "Elm", isGeneric: false,
            source: "https://github.com/elm/compiler/blob/1c278bf5ecf4136f122ce1cba436783c7f561dac/builder/src/Reporting/Exit.hs#L1994-L2001"
        ),
        Definition(
            name: ".pulp-cache", markers: ["bower.json", "psc-package.json"], tool: "Pulp", isGeneric: false,
            source: "https://github.com/purescript-contrib/pulp/blob/78f7aa6ae76337ea6f8362cac03fb1c8ee1858cd/src/Pulp/Project.purs#L57-L62"
        ),
        Definition(
            name: ".psc-package", markers: ["psc-package.json"], tool: "psc-package", isGeneric: false,
            source: "https://github.com/purescript/psc-package/blob/2817cfd7bbc29de790d2ab7bee582cd6167c16b5/docs/faq.md#L11-L20"
        ),
        Definition(
            name: ".spago", markers: ["spago.yaml", "spago.dhall"], tool: "Spago", isGeneric: false,
            source: "https://github.com/purescript/spago/blob/b9ea21cb1416acb724977cba08f1e9325fae358d/README.md#L1589-L1593"
        ),
        // Not beside `bower.json` alone, which projects that never compile PureScript carry too.
        Definition(
            name: "output", markers: ["spago.yaml", "spago.dhall", "psc-package.json"], tool: "PureScript",
            isGeneric: true,
            source: "https://github.com/purescript/purescript/blob/cb3c4965c8468d26c9b14cf0319db6dbd06ee4ff/app/Command/Compile.hs#L81-L85"
        ),
        Definition(
            name: "bower_components", markers: ["bower.json"], tool: "Bower", isGeneric: false,
            source: "https://github.com/bower/bower/blob/4e0c3c1181c21624c5b3ab5bdf5d3becdb172b5a/packages/bower-config/lib/util/defaults.js#L23-L25"
        ),
        // aider runs in any repository, so its tags cache is known by the database diskcache keeps in it.
        Definition(
            name: ".aider.tags.cache.v*", markers: [], tool: "aider", isGeneric: false,
            source: "https://github.com/Aider-AI/aider/blob/5dc9490bb35f9729ef2c95d00a19ccd30c26339c/aider/repomap.py#L33-L43",
            proof: .holds("cache.db")
        ),
        Definition(
            name: ".reco-work", markers: ["main.go"], tool: "reco", isGeneric: false,
            source: "https://github.com/ReconfigureIO/reco/blob/1aaa5f0874528e5da8ce549071aad6e03e1cc3bb/helper.go#L117-L143"
        ),
        // Only what `atspkg clean` removes: never `cbits` or `gen` beside them, where people keep their own C.
        Definition(
            name: ".atspkg", markers: ["atspkg.dhall"], tool: "atspkg", isGeneric: false,
            source: "https://github.com/vmchale/atspkg/blob/26cdd1ed1130a31e4bb4985fc54e50240228f7df/ats-pkg/src/Language/ATS/Package/Build.hs#L69-L76"
        ),
        Definition(
            name: "ats-deps", markers: ["atspkg.dhall"], tool: "atspkg", isGeneric: false,
            source: "https://github.com/vmchale/atspkg/blob/26cdd1ed1130a31e4bb4985fc54e50240228f7df/ats-pkg/src/Language/ATS/Package/Build.hs#L69-L76"
        ),
        // Meson's own test for its build folder, whatever its name. The folder also keeps the options it was set up
        // with, which Meson's `--wipe` carries over and nothing else in the project holds.
        Definition(
            name: "*", markers: ["meson.build"], tool: "Meson", isGeneric: false,
            source: "https://github.com/mesonbuild/meson/blob/d73f48d3b421a25112cc23e5ab629dc68f3d3791/mesonbuild/mcompile.py#L30-L35",
            proof: .holds("meson-private/coredata.dat"), keepsItsSetup: true
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
            source: "https://developer.android.com/ndk/guides/cmake"
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
            source: "https://hexdocs.pm/elixir/introduction-to-mix.html"
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
            name: ".elixir-tools", markers: ["mix.exs"], tool: "Next LS", isGeneric: false,
            source: "https://github.com/elixir-tools/next-ls/blob/eb47c98eef92ffe2b369c7c2bf56ce63b837f949/lib/next_ls/runtime/supervisor.ex#L17-L33"
        ),
        Definition(
            name: ".lexical", markers: ["mix.exs"], tool: "Lexical", isGeneric: false,
            source: "https://github.com/lexical-lsp/lexical/blob/477e8b418b27960710109d0014167bb371b0cade/projects/lexical_shared/lib/lexical/project.ex#L31"
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
        // `.aws-sam` also keeps the pipeline `sam pipeline bootstrap` set up, so only build output is offered.
        Definition(
            name: ".aws-sam/build", markers: samProjectFiles, tool: "AWS SAM", isGeneric: false,
            source: "https://github.com/aws/aws-sam-cli/blob/b73a020cc555abaf6c2cbd3b902b9c91558a3ad9/samcli/commands/_utils/constants.py#L8"
        ),
        Definition(
            name: ".aws-sam/cache", markers: samProjectFiles, tool: "AWS SAM", isGeneric: false,
            source: "https://github.com/aws/aws-sam-cli/blob/b73a020cc555abaf6c2cbd3b902b9c91558a3ad9/samcli/commands/_utils/constants.py#L10"
        ),
        Definition(
            name: ".aws-sam/deps", markers: samProjectFiles, tool: "AWS SAM", isGeneric: false,
            source: "https://github.com/aws/aws-sam-cli/blob/b73a020cc555abaf6c2cbd3b902b9c91558a3ad9/samcli/lib/build/build_graph.py#L32"
        ),
        Definition(
            name: ".aws-sam/auto-dependency-layer", markers: samProjectFiles, tool: "AWS SAM", isGeneric: false,
            source: "https://github.com/aws/aws-sam-cli/blob/b73a020cc555abaf6c2cbd3b902b9c91558a3ad9/samcli/commands/_utils/constants.py#L9"
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

    /// Read again right before a move: the artifacts of `chosen` Peel would suggest whose project has changed in the
    /// last 7 days, or can't be read whole anymore. A folder chosen though Peel didn't suggest it stays chosen. `all`
    /// is every artifact the scan found.
    @concurrent
    public static func changedSinceScan(_ chosen: [ProjectArtifact], among all: [ProjectArtifact]) async -> Set<URL> {
        let suggested = chosen.filter(\.isRecommended)
        guard !suggested.isEmpty else { return [] }
        let activities = await lastActivities(of: suggested.map(\.project), passingBy: all.map(\.url))
        let cutoff = Date.now.addingTimeInterval(-recentlyActive)
        return Set(suggested.filter { artifact in
            guard let activity = activities[key(of: artifact.project)], activity.isCertain else { return true }
            return activity.date.map { $0 > cutoff } ?? false
        }.map(\.url))
    }

    /// Each project's name as a list shows it: its folder's name, or, while another of `projects` has a folder of the
    /// same name, as many folders above it as tell them apart, as in `acme/frontend`.
    public static func names(of projects: [URL]) -> [String] {
        let paths = projects.map { PathComponents.of(key(of: $0)) }
        var lengths = Array(repeating: 1, count: paths.count)
        while true {
            let names = paths.indices.map { paths[$0].suffix(lengths[$0]).joined(separator: "/") }
            var grew = false
            for clash in Dictionary(grouping: paths.indices, by: { names[$0] }).values where clash.count > 1 {
                for index in clash where lengths[index] < paths[index].count {
                    lengths[index] += 1
                    grew = true
                }
            }
            if !grew { return names }
        }
    }

    static let maximumFolders = 40_000
    /// Past this many entries read, a project's last change counts as unknown.
    static let maximumActivitySamples = 10_000

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
        // The kernel's name for the folder: links resolved, each name as the disk holds it, as the walk sees names.
        let kernelName = PathPattern.canonical(root).path(percentEncoded: false)
        let spellings = ([PathPattern.comparablePath(of: root), kernelName]
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
        if SyncedFolders().syncsToOtherDevices(root) { return .inTheCloud }
        if root.isOrIsInsideAPackage { return .inAPackage }
        return PathComponents.of(kernelName).contains(where: isSkipped) ? .neverSearched : nil
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
        var pending: [Pending] = []
        var unreadable: [URL] = []
        var queue = [root]
        // An index, since `removeFirst` would make the walk quadratic.
        var next = 0
        var visited = 0
        var reached: Set<String> = []
        var projectFolders: [String: Bool] = [:]

        while next < queue.count, visited < maximumFolders, !Task.isCancelled {
            let folder = queue[next]
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
            for artifact in look.found {
                reached.insert(Self.key(of: folder.appending(path: artifact.name)))
            }

            for artifact in look.found {
                let url = folder.appending(path: artifact.name)
                let project = artifact.isBesideItsToolsFile
                    ? folder
                    : await project(above: folder, within: root, listing: listing, known: &projectFolders)
                pending.append(Pending(url: url, project: project, found: artifact, contents: await measure(url)))
            }

            for entry in look.entries where !reached.contains(Self.key(of: entry)) {
                guard isRealFolder(entry), !exclusions.excludes(entry), !isSkipped(entry.lastPathComponent) else {
                    continue
                }
                queue.append(entry)
            }
        }
        return (await withLastActivity(pending), next < queue.count, unreadable)
    }

    private struct Pending: Sendable {
        let url: URL
        let project: URL
        let found: Found
        let contents: FolderContents?
    }

    /// Builds write into artifacts while nobody works on a project, so its last change passes by every one inside.
    private static func withLastActivity(_ pending: [Pending]) async -> [ProjectArtifact] {
        let activities = await lastActivities(of: pending.map(\.project), passingBy: pending.map(\.url))
        return pending.map { artifact in
            let activity = activities[key(of: artifact.project)] ?? (date: nil, isCertain: false)
            let heldBack = HoldBack.seen(in: artifact.contents)
            return ProjectArtifact(
                url: artifact.url,
                project: artifact.project,
                name: artifact.found.name,
                tool: artifact.found.definition?.tool,
                size: artifact.contents.flatMap { $0.couldNotBeRead ? nil : $0.size },
                lastActivity: activity.date,
                lastActivityIsCertain: activity.isCertain,
                hasGenericName: artifact.found.definition?.isGeneric ?? false,
                isEnvironment: artifact.found.definition?.isEnvironment ?? false,
                heldBack: (heldBack == .holdsRepository && artifact.found.remakesItsClones ? nil : heldBack)
                    ?? (artifact.found.definition?.keepsItsSetup == true ? .keepsItsSetup : nil)
            )
        }
    }

    /// Each project's last change, keyed by `key(of:)`, passing by every one of `artifacts` inside it, those of the
    /// projects inside it included.
    private static func lastActivities(
        of projects: [URL],
        passingBy artifacts: [URL]
    ) async -> [String: (date: Date?, isCertain: Bool)] {
        let projects = Dictionary(projects.map { (key(of: $0), $0) }, uniquingKeysWith: { first, _ in first })
        var inside: [String: Set<String>] = [:]
        for artifact in artifacts {
            let path = key(of: artifact)
            var above = artifact.deletingLastPathComponent()
            while true {
                let folder = key(of: above)
                if projects[folder] != nil {
                    inside[folder, default: []].insert(String(path.dropFirst(folder.count + 1)))
                }
                guard folder != "/" else { break }
                above = above.deletingLastPathComponent()
            }
        }
        var activities: [String: (date: Date?, isCertain: Bool)] = [:]
        for (project, folder) in projects {
            guard !Task.isCancelled else { break }
            let ignoring = inside[project] ?? []
            activities[project] = await SlowRead.answer(within: FileSize.budget) { isGivenUp in
                lastActivity(in: folder, ignoring: ignoring, isGivenUp: isGivenUp)
            } ?? (date: nil, isCertain: false)
        }
        return activities
    }

    /// The nearest folder from `folder` up to `root` holding a repository or a tool's project file, else `folder`.
    private static func project(
        above folder: URL,
        within root: URL,
        listing: @escaping @Sendable (URL) -> [URL]?,
        known: inout [String: Bool]
    ) async -> URL {
        let top = key(of: root)
        var candidate = folder
        while true {
            let path = key(of: candidate)
            guard path == top || PathComponents.isPath(path, atOrInside: top) else { return folder }
            let isProject: Bool
            if let answer = known[path] {
                isProject = answer
            } else {
                let place = candidate
                isProject = await SlowRead.answer(within: FileSize.budget) { _ in
                    listing(place).map { holdsAProject(names: Set($0.map(\.lastPathComponent)), in: place) } ?? false
                } ?? false
                known[path] = isProject
            }
            if isProject { return candidate }
            guard path != top else { return folder }
            candidate = candidate.deletingLastPathComponent()
        }
    }

    static func holdsAProject(names: Set<String>, in folder: URL) -> Bool {
        !names.isDisjoint(with: FileSize.repositoryMarkers)
            || definitions.contains { !$0.markers.isEmpty && $0.hasMarker(besides: names, in: folder) }
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
        var isBesideItsToolsFile = false

        var remakesItsClones: Bool { isTaggedAsACache && definition?.remakesItsClones == true }
    }

    /// Lists `folder` and finds the artifacts in it, or nil when it cannot be listed.
    private static func look(in folder: URL, exclusions: Exclusions, listing: (URL) -> [URL]?) -> Look? {
        guard let entries = listing(folder) else { return nil }
        // What a folder another app keeps in step holds would go from the other devices too.
        guard !SyncedFolders.marksAFolder(entries) else { return Look(entries: [], found: []) }
        let names = Set(entries.map(\.lastPathComponent))
        var artifactNames: Set<String> = []
        var found: [Found] = []
        for definition in definitions where !definition.isFoundOnlyByItsTag {
            let candidates = definition.candidates(among: names, in: folder)
            guard !candidates.isEmpty, definition.hasMarker(besides: names, in: folder) else { continue }
            for name in candidates {
                let url = folder.appending(path: name)
                guard isRealFolder(url), definition.proof?.holds(at: url) ?? true else { continue }
                guard !exclusions.excludes(url), !exclusions.holds(url) else { continue }
                guard artifactNames.insert(name).inserted else { continue }
                found.append(Found(
                    name: name, definition: definition, isTaggedAsACache: isTaggedAsACache(url),
                    isBesideItsToolsFile: !definition.markers.isEmpty
                ))
            }
        }
        for entry in entries where !artifactNames.contains(entry.lastPathComponent) {
            guard isRealFolder(entry), isTaggedAsACache(entry) else { continue }
            guard !exclusions.excludes(entry), !exclusions.holds(entry) else { continue }
            artifactNames.insert(entry.lastPathComponent)
            // A kind known by its tool's own files, whatever the name, still names the folder away from its project.
            let definition = definitions.first { $0.name == "*" && $0.proof?.holds(at: entry) == true }
            found.append(Found(name: entry.lastPathComponent, definition: definition, isTaggedAsACache: true))
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
        // The project's artifacts are among its entries, so a walk that saw nothing could not read the folder.
        var sawAnything = false
        for case let url as URL in enumerator {
            guard !isGivenUp() else { return (newest, false) }
            sawAnything = true
            let name = url.lastPathComponent
            let relative = String(key(of: url).dropFirst(base.count + 1))
            if artifacts.contains(relative) || passedByForActivity.contains(name) {
                // `skipDescendants()` after a file, such as a submodule's `.git`, would skip the next folder.
                if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                    enumerator.skipDescendants()
                }
                continue
            }
            samples += 1
            guard samples <= maximumActivitySamples else { return (newest, false) }
            guard let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            else { continue }
            if newest == nil || date > newest! { newest = date }
            if date > cutoff { return (date, true) }
        }
        return (newest, newest != nil || sawAnything)
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
