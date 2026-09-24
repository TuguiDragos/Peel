public import Foundation
internal import PeelPrivileged

public struct DeveloperEnvironment: Sendable, Hashable, Identifiable {
    public enum ContentKind: String, Sendable, Hashable {
        case buildData
        case downloads
        case cache
        /// Logs of what a tool did. Nothing makes them again, and no tool needs them to work.
        case logs
        case deviceSupport
        case archives
        /// Model weights and datasets: large, slow to fetch again.
        case models
        /// Installed sets of packages: virtual environments, editor plug-ins, language servers.
        case environments
    }

    public struct Location: Sendable, Hashable, Identifiable {
        public let url: URL
        public let kind: ContentKind
        /// Nil when measuring ran out of time or was refused. Unknown is not the same as empty.
        public let size: Int64?
        /// True when macOS would not let Peel open the folder, rather than it not answering in time.
        public var couldNotBeRead = false

        public var id: URL { url }

        /// Whether Peel selects this location for the user: only content that tools make or fetch again, or
        /// logs, and only once measured. Nothing is selected for the user without showing its size.
        public var isRecommended: Bool {
            switch kind {
            case .buildData, .downloads, .cache, .deviceSupport, .logs: size != nil
            case .archives, .models, .environments: false
            }
        }
    }

    public let id: String
    public let name: String
    public let systemImage: String
    /// The apps that use these locations. The Developer page moves nothing while one of them is running.
    public let appBundleIdentifiers: [String]
    public let locations: [Location]

    public var total: SizeTotal {
        SizeTotal(locations.map(\.size))
    }

    /// The name of one of the environment's apps that is running, which is the one to ask the user to quit.
    /// `name` answers for a bundle identifier with the name of a running copy, or nil when none runs.
    public func runningApp(named name: (String) -> String?) -> String? {
        appBundleIdentifiers.lazy.compactMap(name).first
    }
}

public enum DeveloperCaches {
    struct Definition {
        let id: String
        let name: String
        let systemImage: String
        let appBundleIdentifiers: [String]
        let paths: [(String, DeveloperEnvironment.ContentKind)]
    }

    /// Returns the names of the children of `folder` that this table lists, or lists something inside, as
    /// patterns such as `AndroidStudio*`. Space leaves these folders to the Developer page. Both folders are read
    /// as the kernel names them, so another spelling of the same folder (another case, a link) finds the same.
    static func namesListed(inside folder: URL, home: URL) -> [String] {
        // Not through `comparablePath`: standardizing drops `/private` only from a path that exists, and most
        // paths in the table don't.
        let base = PathComponents.of(PathPattern.canonical(folder).path(percentEncoded: false))
        let home = PathComponents.of(PathPattern.canonical(home).path(percentEncoded: false))
        let names = definitions.flatMap(\.paths).compactMap { path, _ -> String? in
            let full = home + PathComponents.of(path)
            guard full.count > base.count, full.starts(with: base) else { return nil }
            return full[base.count]
        }
        return Array(Set(names)).sorted()
    }

    /// The folders the Developer page offers, relative to the home folder. Only folders one tool owns outright
    /// belong here: no toolchain or installation, nothing holding an account or a token, no path inside another.
    static let definitions: [Definition] = [
        // Apple
        Definition(id: "xcode", name: "Xcode", systemImage: "hammer", appBundleIdentifiers: ["com.apple.dt.Xcode", "com.apple.iphonesimulator"], paths: [
            ("Library/Developer/Xcode/DerivedData", .buildData),
            ("Library/Developer/Xcode/UserData/Previews", .buildData),
            ("Library/Developer/Xcode/iOS DeviceSupport", .deviceSupport),
            ("Library/Developer/Xcode/watchOS DeviceSupport", .deviceSupport),
            ("Library/Developer/Xcode/tvOS DeviceSupport", .deviceSupport),
            ("Library/Developer/Xcode/visionOS DeviceSupport", .deviceSupport),
            ("Library/Developer/Xcode/macOS DeviceSupport", .deviceSupport),
            ("Library/Developer/CoreSimulator/Caches", .cache),
            ("Library/Caches/com.apple.dt.Xcode", .cache),
            ("Library/Developer/Xcode/Archives", .archives),
        ]),
        Definition(id: "swiftpm", name: "Swift Package Manager", systemImage: "swift", appBundleIdentifiers: [], paths: [
            ("Library/Caches/org.swift.swiftpm", .downloads),
        ]),
        Definition(id: "cocoapods", name: "CocoaPods", systemImage: "shippingbox", appBundleIdentifiers: [], paths: [
            ("Library/Caches/CocoaPods", .downloads),
        ]),
        Definition(id: "carthage", name: "Carthage", systemImage: "shippingbox", appBundleIdentifiers: [], paths: [
            ("Library/Caches/org.carthage.CarthageKit", .downloads),
        ]),
        Definition(id: "homebrew", name: "Homebrew", systemImage: "mug", appBundleIdentifiers: [], paths: [
            ("Library/Caches/Homebrew/downloads", .downloads),
            ("Library/Caches/Homebrew/Cask", .downloads),
            ("Library/Caches/Homebrew/bootsnap", .cache),
        ]),
        // JavaScript
        Definition(id: "npm", name: "npm", systemImage: "cube", appBundleIdentifiers: [], paths: [
            (".npm/_cacache", .downloads),
            (".npm/_npx", .downloads),
        ]),
        Definition(id: "yarn", name: "Yarn", systemImage: "cube", appBundleIdentifiers: [], paths: [
            ("Library/Caches/Yarn", .downloads),
            // Yarn's Plug'n'Play projects load every package from this cache, so it is listed and never selected:
            // moving it breaks each such project until `yarn install` runs in it again.
            (".yarn/berry/cache", .environments),
        ]),
        Definition(id: "pnpm", name: "pnpm", systemImage: "cube", appBundleIdentifiers: [], paths: [
            ("Library/pnpm/store", .environments),
            ("Library/Caches/pnpm", .cache),
        ]),
        Definition(id: "bun", name: "Bun", systemImage: "cube", appBundleIdentifiers: [], paths: [
            (".bun/install/cache", .downloads),
        ]),
        Definition(id: "deno", name: "Deno", systemImage: "chevron.left.forwardslash.chevron.right", appBundleIdentifiers: [], paths: [
            ("Library/Caches/deno", .downloads),
        ]),
        Definition(id: "reactnative", name: "React Native CLI", systemImage: "cube", appBundleIdentifiers: [], paths: [
            ("Library/Caches/react-native-cli", .cache),
        ]),
        Definition(id: "expo", name: "Expo", systemImage: "cube", appBundleIdentifiers: [], paths: [
            (".expo/expo-go", .downloads),
            (".expo/versions-cache", .cache),
            (".expo/ios-simulator-app-cache", .downloads),
            (".expo/android-apk-cache", .downloads),
        ]),
        Definition(id: "nx", name: "Nx", systemImage: "cube", appBundleIdentifiers: [], paths: [
            (".nx/*/cache", .buildData),
            (".nx/*/databases", .cache),
        ]),
        Definition(id: "playwright", name: "Playwright", systemImage: "globe", appBundleIdentifiers: [], paths: [
            ("Library/Caches/ms-playwright", .downloads),
        ]),
        Definition(id: "cypress", name: "Cypress", systemImage: "globe", appBundleIdentifiers: [], paths: [
            ("Library/Caches/Cypress", .downloads),
        ]),
        Definition(id: "puppeteer", name: "Puppeteer", systemImage: "globe", appBundleIdentifiers: [], paths: [
            (".cache/puppeteer", .downloads),
        ]),
        Definition(id: "electron", name: "Electron", systemImage: "cube", appBundleIdentifiers: [], paths: [
            ("Library/Caches/electron", .downloads),
            ("Library/Caches/electron-builder", .downloads),
            (".electron-gyp", .downloads),
        ]),
        Definition(id: "nodegyp", name: "node-gyp", systemImage: "cube", appBundleIdentifiers: [], paths: [
            ("Library/Caches/node-gyp", .downloads),
            (".node-gyp", .downloads),
        ]),
        Definition(id: "typescript", name: "TypeScript", systemImage: "cube", appBundleIdentifiers: [], paths: [
            ("Library/Caches/typescript", .downloads),
        ]),
        // Python
        Definition(id: "pip", name: "pip", systemImage: "chevron.left.forwardslash.chevron.right", appBundleIdentifiers: [], paths: [
            ("Library/Caches/pip", .downloads),
        ]),
        Definition(id: "poetry", name: "Poetry", systemImage: "chevron.left.forwardslash.chevron.right", appBundleIdentifiers: [], paths: [
            ("Library/Caches/pypoetry/cache", .downloads),
            ("Library/Caches/pypoetry/artifacts", .downloads),
            ("Library/Caches/pypoetry/virtualenvs", .environments),
        ]),
        Definition(id: "uv", name: "uv", systemImage: "chevron.left.forwardslash.chevron.right", appBundleIdentifiers: [], paths: [
            (".cache/uv", .environments),
        ]),
        Definition(id: "precommit", name: "pre-commit", systemImage: "chevron.left.forwardslash.chevron.right", appBundleIdentifiers: [], paths: [
            (".cache/pre-commit", .cache),
        ]),
        Definition(id: "pipenv", name: "Pipenv", systemImage: "chevron.left.forwardslash.chevron.right", appBundleIdentifiers: [], paths: [
            ("Library/Caches/pipenv", .downloads),
            (".local/share/virtualenvs", .environments),
        ]),
        Definition(id: "virtualenvwrapper", name: "virtualenvwrapper", systemImage: "chevron.left.forwardslash.chevron.right", appBundleIdentifiers: [], paths: [
            (".virtualenvs", .environments),
        ]),
        Definition(id: "conda", name: "Conda", systemImage: "chevron.left.forwardslash.chevron.right", appBundleIdentifiers: [], paths: [
            ("miniconda3/pkgs", .environments),
            ("anaconda3/pkgs", .environments),
            (".conda/pkgs", .environments),
        ]),
        // Rust and Go
        Definition(id: "cargo", name: "Cargo", systemImage: "gearshape.2", appBundleIdentifiers: [], paths: [
            (".cargo/registry/cache", .downloads),
            (".cargo/registry/index", .downloads),
            (".cargo/registry/src", .downloads),
            (".cargo/git/checkouts", .downloads),
        ]),
        Definition(id: "go", name: "Go", systemImage: "chevron.left.forwardslash.chevron.right", appBundleIdentifiers: [], paths: [
            ("Library/Caches/go-build", .buildData),
            ("go/pkg/mod/cache/download", .downloads),
        ]),
        Definition(id: "sccache", name: "sccache", systemImage: "gearshape.2", appBundleIdentifiers: [], paths: [
            ("Library/Caches/Mozilla.sccache", .buildData),
        ]),
        // JVM and Android
        Definition(id: "gradle", name: "Gradle", systemImage: "cup.and.saucer", appBundleIdentifiers: [], paths: [
            (".gradle/caches", .downloads),
            (".gradle/wrapper/dists", .downloads),
            (".gradle/daemon", .cache),
        ]),
        Definition(id: "maven", name: "Maven", systemImage: "cup.and.saucer", appBundleIdentifiers: [], paths: [
            (".m2/repository", .environments),
        ]),
        Definition(id: "sbt", name: "sbt & Coursier", systemImage: "cup.and.saucer", appBundleIdentifiers: [], paths: [
            (".sbt/boot", .downloads),
            (".ivy2/cache", .downloads),
            // Only the cache. `Coursier/jvm` beside it holds the JVMs `cs java` installed, which `JAVA_HOME`
            // points at (https://get-coursier.io/docs/cache and https://get-coursier.io/docs/cli-java).
            ("Library/Caches/Coursier/v1", .downloads),
        ]),
        Definition(id: "konan", name: "Kotlin/Native", systemImage: "cup.and.saucer", appBundleIdentifiers: [], paths: [
            (".konan/dependencies", .downloads),
            (".konan/cache", .buildData),
        ]),
        // Other languages
        Definition(id: "dart", name: "Dart & Flutter", systemImage: "chevron.left.forwardslash.chevron.right", appBundleIdentifiers: [], paths: [
            (".pub-cache/hosted", .downloads),
        ]),
        Definition(id: "composer", name: "Composer", systemImage: "chevron.left.forwardslash.chevron.right", appBundleIdentifiers: [], paths: [
            ("Library/Caches/composer", .downloads),
            (".composer/cache", .downloads),
        ]),
        Definition(id: "rubygems", name: "RubyGems & Bundler", systemImage: "shippingbox", appBundleIdentifiers: [], paths: [
            (".gem/ruby/*/cache", .downloads),
            (".gem/specs", .cache),
            (".cache/gem/gems", .downloads),
            (".cache/gem/specs", .cache),
            (".bundle/cache", .downloads),
        ]),
        Definition(id: "nuget", name: "NuGet", systemImage: "shippingbox", appBundleIdentifiers: [], paths: [
            (".nuget/packages", .downloads),
            (".local/share/NuGet/v3-cache", .cache),
            (".local/share/NuGet/plugins-cache", .cache),
        ]),
        Definition(id: "julia", name: "Julia", systemImage: "chevron.left.forwardslash.chevron.right", appBundleIdentifiers: [], paths: [
            (".julia/artifacts", .downloads),
            (".julia/clones", .downloads),
            (".julia/compiled", .buildData),
            (".julia/scratchspaces", .cache),
        ]),
        Definition(id: "nix", name: "Nix", systemImage: "shippingbox", appBundleIdentifiers: [], paths: [
            (".cache/nix", .cache),
        ]),
        // Editors
        // A JetBrains IDE keeps `LocalHistory` beside its caches: the edits it recorded while a project was
        // open, which are in no repository and nowhere else. The cache folders are listed one by one, so
        // `LocalHistory` is never removed with them.
        Definition(id: "jetbrains", name: "JetBrains IDEs", systemImage: "curlybraces", appBundleIdentifiers: [
            "com.jetbrains.intellij", "com.jetbrains.intellij.ce", "com.jetbrains.pycharm", "com.jetbrains.pycharm.ce",
            "com.jetbrains.WebStorm", "com.jetbrains.PhpStorm", "com.jetbrains.goland", "com.jetbrains.rubymine",
            "com.jetbrains.CLion", "com.jetbrains.rider", "com.jetbrains.datagrip", "com.jetbrains.AppCode",
            "com.jetbrains.rustrover", "com.google.android.studio",
        ], paths: [
            ("Library/Caches/JetBrains/*/caches", .cache),
            ("Library/Caches/JetBrains/*/index", .cache),
            ("Library/Caches/JetBrains/*/tmp", .cache),
            ("Library/Logs/JetBrains", .logs),
        ]),
        Definition(id: "vscode", name: "Visual Studio Code", systemImage: "curlybraces", appBundleIdentifiers: ["com.microsoft.VSCode"], paths: [
            ("Library/Application Support/Code/Cache", .cache),
            ("Library/Application Support/Code/CachedData", .cache),
            ("Library/Application Support/Code/CachedExtensionVSIXs", .downloads),
        ]),
        Definition(id: "vscodium", name: "VSCodium", systemImage: "curlybraces", appBundleIdentifiers: ["com.vscodium"], paths: [
            ("Library/Application Support/VSCodium/Cache", .cache),
            ("Library/Application Support/VSCodium/CachedData", .cache),
            ("Library/Application Support/VSCodium/CachedExtensionVSIXs", .downloads),
            ("Library/Caches/com.vscodium", .cache),
        ]),
        Definition(id: "cursor", name: "Cursor", systemImage: "curlybraces", appBundleIdentifiers: ["com.todesktop.230313mzl4w4u92"], paths: [
            ("Library/Application Support/Cursor/Cache", .cache),
            ("Library/Application Support/Cursor/CachedData", .cache),
            ("Library/Application Support/Caches/cursor-updater", .downloads),
        ]),
        Definition(id: "windsurf", name: "Windsurf & Devin", systemImage: "curlybraces", appBundleIdentifiers: ["com.exafunction.windsurf", "ai.cognition.devin"], paths: [
            ("Library/Application Support/Devin/Cache", .cache),
            ("Library/Application Support/Devin/CachedData", .cache),
            ("Library/Application Support/Windsurf/Cache", .cache),
            ("Library/Application Support/Windsurf/CachedData", .cache),
        ]),
        Definition(id: "nova", name: "Nova", systemImage: "curlybraces", appBundleIdentifiers: ["com.panic.Nova"], paths: [
            ("Library/Caches/com.panic.Nova", .cache),
        ]),
        Definition(id: "zed", name: "Zed", systemImage: "curlybraces", appBundleIdentifiers: ["dev.zed.Zed"], paths: [
            ("Library/Caches/Zed", .cache),
        ]),
        Definition(id: "sublime", name: "Sublime Text", systemImage: "curlybraces", appBundleIdentifiers: ["com.sublimetext.4", "com.sublimetext.3"], paths: [
            ("Library/Caches/Sublime Text", .cache),
            ("Library/Caches/com.sublimetext.4", .cache),
            ("Library/Caches/Sublime Text 3", .cache),
            ("Library/Caches/com.sublimetext.3", .cache),
        ]),
        Definition(id: "androidstudio", name: "Android Studio", systemImage: "curlybraces", appBundleIdentifiers: ["com.google.android.studio"], paths: [
            ("Library/Caches/Google/AndroidStudio*/caches", .cache),
            ("Library/Caches/Google/AndroidStudio*/index", .cache),
            ("Library/Caches/Google/AndroidStudio*/tmp", .cache),
            ("Library/Logs/Google/AndroidStudio*", .logs),
        ]),
        Definition(id: "neovim", name: "Neovim", systemImage: "curlybraces", appBundleIdentifiers: [], paths: [
            (".cache/nvim", .cache),
            (".local/share/nvim/lazy", .environments),
            (".local/share/nvim/lazy-rocks", .environments),
            (".local/share/nvim/mason", .environments),
            (".local/state/nvim/lazy", .cache),
        ]),
        // Cloud tools
        Definition(id: "gcloud", name: "Google Cloud CLI", systemImage: "cloud", appBundleIdentifiers: [], paths: [
            (".config/gcloud/cache", .cache),
            (".config/gcloud/logs", .logs),
        ]),
        Definition(id: "azure", name: "Azure CLI", systemImage: "cloud", appBundleIdentifiers: [], paths: [
            (".azure/logs", .logs),
            (".azure/telemetry", .cache),
        ]),
        Definition(id: "kubectl", name: "kubectl", systemImage: "cloud", appBundleIdentifiers: [], paths: [
            (".kube/cache/discovery", .cache),
            (".kube/cache/http", .cache),
        ]),
        Definition(id: "helm", name: "Helm", systemImage: "cloud", appBundleIdentifiers: [], paths: [
            ("Library/Caches/helm", .cache),
        ]),
        Definition(id: "githubcli", name: "GitHub CLI", systemImage: "cloud", appBundleIdentifiers: [], paths: [
            (".cache/gh", .cache),
        ]),
        Definition(id: "terraform", name: "Terraform", systemImage: "cloud", appBundleIdentifiers: [], paths: [
            (".terraform.d/plugin-cache", .environments),
        ]),
        Definition(id: "pulumi", name: "Pulumi", systemImage: "cloud", appBundleIdentifiers: [], paths: [
            (".pulumi/plugins", .downloads),
        ]),
        Definition(id: "vercel", name: "Vercel CLI", systemImage: "cloud", appBundleIdentifiers: [], paths: [
            ("Library/Caches/com.vercel", .cache),
            ("Library/Caches/com.vercel.cli", .cache),
        ]),
        // Netlify keeps its token in `config.json` in the same folder, so only these two subfolders are listed.
        Definition(id: "netlify", name: "Netlify CLI", systemImage: "cloud", appBundleIdentifiers: [], paths: [
            ("Library/Preferences/netlify/deno-cli", .downloads),
            ("Library/Preferences/netlify/tunnel", .downloads),
        ]),
        Definition(id: "firebase", name: "Firebase CLI", systemImage: "cloud", appBundleIdentifiers: [], paths: [
            (".cache/firebase", .downloads),
        ]),
        // Build systems and media
        Definition(id: "ccache", name: "ccache", systemImage: "gearshape.2", appBundleIdentifiers: [], paths: [
            ("Library/Caches/ccache", .buildData),
            // A legacy `~/.ccache` also holds `ccache.conf` (https://ccache.dev/manual/latest.html), so only
            // the cache's own shards and its temporary folder are named.
            (".ccache/[0-9a-f]", .buildData),
            (".ccache/tmp", .buildData),
        ]),
        Definition(id: "bazel", name: "Bazel", systemImage: "gearshape.2", appBundleIdentifiers: [], paths: [
            ("Library/Caches/bazel", .buildData),
            ("Library/Caches/bazelisk", .downloads),
        ]),
        Definition(id: "unity", name: "Unity", systemImage: "cube.transparent", appBundleIdentifiers: [], paths: [
            // The Package Manager's cache of downloaded packages: `Library/Unity/cache` up to Unity 2022.3, and
            // `Library/Caches/Unity/upm` from Unity 6 (docs.unity3d.com, Manual/upm-cache.html for each version).
            ("Library/Caches/Unity/upm", .downloads),
            ("Library/Unity/cache", .downloads),
        ]),
        Definition(id: "unreal", name: "Unreal Engine", systemImage: "cube.transparent", appBundleIdentifiers: [], paths: [
            ("Library/Application Support/Epic/Zen/Data", .buildData),
            ("Library/Application Support/Epic/UnrealEngine/Common/DerivedDataCache", .buildData),
        ]),
        Definition(id: "blender", name: "Blender", systemImage: "cube.transparent", appBundleIdentifiers: ["org.blenderfoundation.blender"], paths: [
            ("Library/Caches/Blender", .cache),
        ]),
        Definition(id: "adobe", name: "Adobe Media Cache", systemImage: "play.rectangle", appBundleIdentifiers: [], paths: [
            ("Library/Application Support/Adobe/Common/Media Cache Files", .cache),
            ("Library/Application Support/Adobe/Common/Media Cache", .cache),
        ]),
        // Quantum computing. Everything else these SDKs write in the home folder is settings or an account
        // token, so only these three folders are listed.
        Definition(id: "dwave", name: "D-Wave Ocean", systemImage: "atom", appBundleIdentifiers: [], paths: [
            ("Library/Caches/dwave-cloud-client", .cache),
        ]),
        Definition(id: "qutip", name: "QuTiP", systemImage: "atom", appBundleIdentifiers: [], paths: [
            (".qutip/qutip_coeffs_*", .buildData),
        ]),
        Definition(id: "qbraid", name: "qBraid", systemImage: "atom", appBundleIdentifiers: [], paths: [
            (".qbraid/environments", .environments),
        ]),

        // Models and datasets
        Definition(id: "ollama", name: "Ollama", systemImage: "brain", appBundleIdentifiers: [], paths: [
            (".ollama/models", .models),
            (".ollama/logs", .logs),
        ]),
        Definition(id: "lmstudio", name: "LM Studio", systemImage: "brain", appBundleIdentifiers: [], paths: [
            (".lmstudio/models", .models),
            (".cache/lm-studio/models", .models),
        ]),
        Definition(id: "huggingface", name: "Hugging Face", systemImage: "brain", appBundleIdentifiers: [], paths: [
            (".cache/huggingface/hub", .models),
            (".cache/huggingface/datasets", .models),
            (".cache/huggingface/xet", .cache),
            (".cache/huggingface/assets", .cache),
            (".cache/huggingface/transformers", .models),
        ]),
        Definition(id: "torch", name: "PyTorch", systemImage: "brain", appBundleIdentifiers: [], paths: [
            (".cache/torch/hub", .models),
            (".cache/torch/transformers", .models),
        ]),
        Definition(id: "mlxdata", name: "MLX Data", systemImage: "brain", appBundleIdentifiers: [], paths: [
            (".cache/mlx.data", .models),
        ]),
        Definition(id: "whisper", name: "Whisper", systemImage: "brain", appBundleIdentifiers: [], paths: [
            (".cache/whisper", .models),
        ]),
        Definition(id: "gpt4all", name: "GPT4All", systemImage: "brain", appBundleIdentifiers: [], paths: [
            (".cache/gpt4all", .models),
        ]),
        Definition(id: "tensorflow", name: "TensorFlow Datasets", systemImage: "brain", appBundleIdentifiers: [], paths: [
            ("tensorflow_datasets", .models),
        ]),
        Definition(id: "keras", name: "Keras", systemImage: "brain", appBundleIdentifiers: [], paths: [
            (".keras/datasets", .models),
            (".keras/models", .models),
        ]),
        Definition(id: "nltk", name: "NLTK Data", systemImage: "brain", appBundleIdentifiers: [], paths: [
            ("nltk_data", .models),
        ]),
    ]

    @concurrent
    public static func scan(homeDirectory: URL = .homeDirectory, exclusions: Exclusions = .none) async -> [DeveloperEnvironment] {
        await scan(definitions, homeDirectory: homeDirectory, exclusions: exclusions)
    }

    static func scan(
        _ definitions: [Definition],
        homeDirectory: URL,
        exclusions: Exclusions = .none,
        measure: @escaping LeftoverScanner.Measure = LeftoverScanner.walk
    ) async -> [DeveloperEnvironment] {
        await withTaskGroup(of: DeveloperEnvironment?.self) { group in
            for definition in definitions {
                _ = group.addTaskUnlessCancelled {
                    var locations: [DeveloperEnvironment.Location] = []
                    for (path, kind) in definition.paths {
                        for url in PathPattern.expand(path, home: homeDirectory) {
                            guard !Task.isCancelled else { return nil }
                            guard !exclusions.excludes(url), !exclusions.holds(url) else { continue }
                            // Skips a folder that holds work kept nowhere else, such as the state Deno's
                            // scripts keep in `location_data`. Removing it would lose that work.
                            guard !ProtectedData.holdsWorkKeptInACache(url.path(percentEncoded: false)) else { continue }
                            // Skips a symbolic link, which is how people move a big cache to another disk.
                            // Moving the link frees nothing.
                            guard (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else { continue }
                            // Awaited, never blocked on: every tool in the table is measured at once, and a
                            // blocked wait would hold one of the few threads that every scan in the app shares.
                            let contents = await measure(url)
                            locations.append(DeveloperEnvironment.Location(
                                url: url,
                                kind: kind,
                                size: contents.flatMap { $0.couldNotBeRead ? nil : $0.size },
                                couldNotBeRead: contents?.couldNotBeRead == true
                            ))
                        }
                    }
                    guard !locations.isEmpty else { return nil }
                    return DeveloperEnvironment(
                        id: definition.id,
                        name: definition.name,
                        systemImage: definition.systemImage,
                        appBundleIdentifiers: definition.appBundleIdentifiers,
                        locations: locations.sorted { SizeTotal([$0.size]) > SizeTotal([$1.size]) }
                    )
                }
            }
            return await group.reduce(into: [DeveloperEnvironment]()) { environments, environment in
                if let environment { environments.append(environment) }
            }
            .sorted { $0.total != $1.total ? $0.total > $1.total : $0.name < $1.name }
        }
    }
}
