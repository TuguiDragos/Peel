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
        let folders: [Folder]
    }

    /// A folder a tool keeps, relative to the home folder, and what it holds.
    struct Folder {
        let path: String
        let kind: DeveloperEnvironment.ContentKind
        /// A store the tool can turn on inside the folder, which projects then link into. While an entry by that
        /// name is there, a link included, the folder is listed without a checkmark: moving it breaks them.
        let storeInside: String?

        init(_ path: String, _ kind: DeveloperEnvironment.ContentKind, storeInside: String? = nil) {
            self.path = path
            self.kind = kind
            self.storeInside = storeInside
        }

        /// What the folder at `url` holds now: installed packages once its store is there, `kind` otherwise.
        func kind(at url: URL) -> DeveloperEnvironment.ContentKind {
            guard let storeInside else { return kind }
            let store = url.appending(path: storeInside).path(percentEncoded: false)
            return (try? FileManager.default.attributesOfItem(atPath: store)) != nil ? .environments : kind
        }
    }

    /// Returns the names of the children of `folder` that this table lists, or lists something inside, as
    /// patterns such as `AndroidStudio*`. Space leaves these folders to the Developer page. Both folders are read
    /// as the kernel names them, so another spelling of the same folder (another case, a link) finds the same.
    static func namesListed(inside folder: URL, home: URL) -> [String] {
        // Not through `comparablePath`: standardizing drops `/private` only from a path that exists, and most
        // paths in the table don't.
        let base = PathComponents.of(PathPattern.canonical(folder).path(percentEncoded: false))
        let home = PathComponents.of(PathPattern.canonical(home).path(percentEncoded: false))
        let names = definitions.flatMap(\.folders).compactMap { folder -> String? in
            let full = home + PathComponents.of(folder.path)
            guard full.count > base.count, full.starts(with: base) else { return nil }
            return full[base.count]
        }
        return Array(Set(names)).sorted()
    }

    /// The folders the Developer page offers, relative to the home folder. Only folders one tool owns outright
    /// belong here: no toolchain or installation, nothing holding an account or a token, no path inside another.
    static let definitions: [Definition] = [
        // Apple
        Definition(id: "xcode", name: "Xcode", systemImage: "hammer", appBundleIdentifiers: ["com.apple.dt.Xcode", "com.apple.iphonesimulator"], folders: [
            Folder("Library/Developer/Xcode/DerivedData", .buildData),
            Folder("Library/Developer/Xcode/UserData/Previews/Simulator Devices", .buildData),
            Folder("Library/Developer/Xcode/iOS DeviceSupport", .deviceSupport),
            Folder("Library/Developer/Xcode/watchOS DeviceSupport", .deviceSupport),
            Folder("Library/Developer/Xcode/tvOS DeviceSupport", .deviceSupport),
            Folder("Library/Developer/Xcode/visionOS DeviceSupport", .deviceSupport),
            Folder("Library/Developer/Xcode/macOS DeviceSupport", .deviceSupport),
            Folder("Library/Developer/CoreSimulator/Caches", .cache),
            Folder("Library/Caches/com.apple.dt.Xcode", .cache),
            Folder("Library/Developer/Xcode/Archives", .archives),
        ]),
        Definition(id: "swiftpm", name: "Swift Package Manager", systemImage: "swift", appBundleIdentifiers: [], folders: [
            Folder("Library/Caches/org.swift.swiftpm", .downloads),
        ]),
        Definition(id: "cocoapods", name: "CocoaPods", systemImage: "shippingbox", appBundleIdentifiers: [], folders: [
            Folder("Library/Caches/CocoaPods", .downloads),
        ]),
        Definition(id: "carthage", name: "Carthage", systemImage: "shippingbox", appBundleIdentifiers: [], folders: [
            Folder("Library/Caches/org.carthage.CarthageKit", .downloads),
        ]),
        Definition(id: "homebrew", name: "Homebrew", systemImage: "mug", appBundleIdentifiers: [], folders: [
            Folder("Library/Caches/Homebrew/downloads", .downloads),
            Folder("Library/Caches/Homebrew/Cask", .downloads),
            Folder("Library/Caches/Homebrew/bootsnap", .cache),
        ]),
        // JavaScript
        Definition(id: "npm", name: "npm", systemImage: "cube", appBundleIdentifiers: [], folders: [
            Folder(".npm/_cacache", .downloads),
            Folder(".npm/_npx", .downloads),
        ]),
        Definition(id: "yarn", name: "Yarn", systemImage: "cube", appBundleIdentifiers: [], folders: [
            Folder("Library/Caches/Yarn", .downloads),
            // Yarn's Plug'n'Play projects load every package from this cache, so it is listed and never selected:
            // moving it breaks each such project until `yarn install` runs in it again.
            Folder(".yarn/berry/cache", .environments),
        ]),
        Definition(id: "pnpm", name: "pnpm", systemImage: "cube", appBundleIdentifiers: [], folders: [
            Folder("Library/pnpm/store", .environments),
            Folder("Library/Caches/pnpm", .cache),
        ]),
        Definition(id: "bun", name: "Bun", systemImage: "cube", appBundleIdentifiers: [], folders: [
            // Bun's global virtual store, once turned on, is `links`, and every project's `node_modules` then points
            // into it (Bun's documentation, "Global virtual store").
            Folder(".bun/install/cache", .downloads, storeInside: "links"),
        ]),
        Definition(id: "deno", name: "Deno", systemImage: "chevron.left.forwardslash.chevron.right", appBundleIdentifiers: [], folders: [
            // `DENO_DIR` keeps the REPL history (`deno_history.txt`) and what scripts store (`location_data`)
            // beside its caches, so the caches are named one by one, as Deno's `deno_dir.rs` names them. `deps` and
            // the `_v1` databases are Deno 1's names.
            Folder("Library/Caches/deno/remote", .downloads),
            Folder("Library/Caches/deno/deps", .downloads),
            Folder("Library/Caches/deno/npm", .downloads),
            Folder("Library/Caches/deno/dl", .downloads),
            Folder("Library/Caches/deno/gen", .buildData),
            Folder("Library/Caches/deno/registries", .cache),
            Folder("Library/Caches/deno/*_cache_v1", .cache),
            Folder("Library/Caches/deno/*_cache_v2", .cache),
        ]),
        Definition(id: "reactnative", name: "React Native CLI", systemImage: "cube", appBundleIdentifiers: [], folders: [
            Folder("Library/Caches/react-native-cli", .cache),
        ]),
        Definition(id: "expo", name: "Expo", systemImage: "cube", appBundleIdentifiers: [], folders: [
            Folder(".expo/expo-go", .downloads),
            Folder(".expo/versions-cache", .cache),
            Folder(".expo/ios-simulator-app-cache", .downloads),
            Folder(".expo/android-apk-cache", .downloads),
        ]),
        Definition(id: "nx", name: "Nx", systemImage: "cube", appBundleIdentifiers: [], folders: [
            // One workspace's `cache` and `databases`, named by 16 hex digits of a hash. They go together: Nx
            // answers a cache hit from the database alone, and a database without its cache restores nothing.
            Folder(".nx/" + String(repeating: "[0-9a-f]", count: 16), .buildData),
        ]),
        Definition(id: "playwright", name: "Playwright", systemImage: "globe", appBundleIdentifiers: [], folders: [
            Folder("Library/Caches/ms-playwright", .downloads),
        ]),
        Definition(id: "cypress", name: "Cypress", systemImage: "globe", appBundleIdentifiers: [], folders: [
            Folder("Library/Caches/Cypress", .downloads),
        ]),
        Definition(id: "puppeteer", name: "Puppeteer", systemImage: "globe", appBundleIdentifiers: [], folders: [
            Folder(".cache/puppeteer", .downloads),
        ]),
        Definition(id: "electron", name: "Electron", systemImage: "cube", appBundleIdentifiers: [], folders: [
            Folder("Library/Caches/electron", .downloads),
            Folder("Library/Caches/electron-builder", .downloads),
            Folder(".electron-gyp", .downloads),
        ]),
        Definition(id: "nodegyp", name: "node-gyp", systemImage: "cube", appBundleIdentifiers: [], folders: [
            Folder("Library/Caches/node-gyp", .downloads),
            Folder(".node-gyp", .downloads),
        ]),
        Definition(id: "typescript", name: "TypeScript", systemImage: "cube", appBundleIdentifiers: [], folders: [
            Folder("Library/Caches/typescript", .downloads),
        ]),
        // Python
        Definition(id: "pip", name: "pip", systemImage: "chevron.left.forwardslash.chevron.right", appBundleIdentifiers: [], folders: [
            Folder("Library/Caches/pip", .downloads),
        ]),
        Definition(id: "poetry", name: "Poetry", systemImage: "chevron.left.forwardslash.chevron.right", appBundleIdentifiers: [], folders: [
            Folder("Library/Caches/pypoetry/cache", .downloads),
            Folder("Library/Caches/pypoetry/artifacts", .downloads),
            Folder("Library/Caches/pypoetry/virtualenvs", .environments),
        ]),
        Definition(id: "uv", name: "uv", systemImage: "chevron.left.forwardslash.chevron.right", appBundleIdentifiers: [], folders: [
            Folder(".cache/uv", .environments),
        ]),
        Definition(id: "precommit", name: "pre-commit", systemImage: "chevron.left.forwardslash.chevron.right", appBundleIdentifiers: [], folders: [
            Folder(".cache/pre-commit", .cache),
        ]),
        Definition(id: "pipenv", name: "Pipenv", systemImage: "chevron.left.forwardslash.chevron.right", appBundleIdentifiers: [], folders: [
            Folder("Library/Caches/pipenv", .downloads),
            Folder(".local/share/virtualenvs", .environments),
        ]),
        Definition(id: "virtualenvwrapper", name: "virtualenvwrapper", systemImage: "chevron.left.forwardslash.chevron.right", appBundleIdentifiers: [], folders: [
            // The environments, not the hook scripts virtualenvwrapper keeps beside them: a pattern that ends in `/`
            // matches folders only.
            Folder(".virtualenvs/*/", .environments),
        ]),
        Definition(id: "conda", name: "Conda", systemImage: "chevron.left.forwardslash.chevron.right", appBundleIdentifiers: [], folders: [
            Folder("miniconda3/pkgs", .environments),
            Folder("anaconda3/pkgs", .environments),
            Folder(".conda/pkgs", .environments),
        ]),
        // Rust and Go
        Definition(id: "cargo", name: "Cargo", systemImage: "gearshape.2", appBundleIdentifiers: [], folders: [
            Folder(".cargo/registry/cache", .downloads),
            Folder(".cargo/registry/index", .downloads),
            Folder(".cargo/registry/src", .downloads),
            Folder(".cargo/git/checkouts", .downloads),
        ]),
        Definition(id: "go", name: "Go", systemImage: "chevron.left.forwardslash.chevron.right", appBundleIdentifiers: [], folders: [
            Folder("Library/Caches/go-build", .buildData),
            Folder("go/pkg/mod/cache/download", .downloads),
        ]),
        Definition(id: "sccache", name: "sccache", systemImage: "gearshape.2", appBundleIdentifiers: [], folders: [
            Folder("Library/Caches/Mozilla.sccache", .buildData),
        ]),
        // JVM and Android
        Definition(id: "gradle", name: "Gradle", systemImage: "cup.and.saucer", appBundleIdentifiers: [], folders: [
            Folder(".gradle/caches", .downloads),
            Folder(".gradle/wrapper/dists", .downloads),
            Folder(".gradle/daemon", .cache),
        ]),
        Definition(id: "maven", name: "Maven", systemImage: "cup.and.saucer", appBundleIdentifiers: [], folders: [
            Folder(".m2/repository", .environments),
        ]),
        Definition(id: "sbt", name: "sbt & Coursier", systemImage: "cup.and.saucer", appBundleIdentifiers: [], folders: [
            Folder(".sbt/boot", .downloads),
            Folder(".ivy2/cache", .downloads),
            // Only the cache. `Coursier/jvm` beside it holds the JVMs `cs java` installed, which `JAVA_HOME`
            // points at (https://get-coursier.io/docs/cache and https://get-coursier.io/docs/cli-java).
            Folder("Library/Caches/Coursier/v1", .downloads),
        ]),
        Definition(id: "konan", name: "Kotlin/Native", systemImage: "cup.and.saucer", appBundleIdentifiers: [], folders: [
            Folder(".konan/dependencies", .downloads),
            Folder(".konan/cache", .buildData),
        ]),
        // Other languages
        Definition(id: "dart", name: "Dart & Flutter", systemImage: "chevron.left.forwardslash.chevron.right", appBundleIdentifiers: [], folders: [
            Folder(".pub-cache/hosted", .downloads),
        ]),
        Definition(id: "composer", name: "Composer", systemImage: "chevron.left.forwardslash.chevron.right", appBundleIdentifiers: [], folders: [
            Folder("Library/Caches/composer", .downloads),
            Folder(".composer/cache", .downloads),
        ]),
        Definition(id: "rubygems", name: "RubyGems & Bundler", systemImage: "shippingbox", appBundleIdentifiers: [], folders: [
            Folder(".gem/ruby/*/cache", .downloads),
            Folder(".gem/specs", .cache),
            Folder(".cache/gem/gems", .downloads),
            Folder(".cache/gem/specs", .cache),
            Folder(".bundle/cache", .downloads),
        ]),
        Definition(id: "nuget", name: "NuGet", systemImage: "shippingbox", appBundleIdentifiers: [], folders: [
            Folder(".nuget/packages", .downloads),
            Folder(".local/share/NuGet/v3-cache", .cache),
            Folder(".local/share/NuGet/plugins-cache", .cache),
        ]),
        Definition(id: "julia", name: "Julia", systemImage: "chevron.left.forwardslash.chevron.right", appBundleIdentifiers: [], folders: [
            Folder(".julia/artifacts", .downloads),
            Folder(".julia/clones", .downloads),
            Folder(".julia/compiled", .buildData),
            Folder(".julia/scratchspaces", .cache),
        ]),
        Definition(id: "nix", name: "Nix", systemImage: "shippingbox", appBundleIdentifiers: [], folders: [
            Folder(".cache/nix", .cache),
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
        ], folders: [
            Folder("Library/Caches/JetBrains/*/caches", .cache),
            Folder("Library/Caches/JetBrains/*/index", .cache),
            Folder("Library/Caches/JetBrains/*/tmp", .cache),
            Folder("Library/Logs/JetBrains", .logs),
        ]),
        Definition(id: "vscode", name: "Visual Studio Code", systemImage: "curlybraces", appBundleIdentifiers: ["com.microsoft.VSCode"], folders: [
            Folder("Library/Application Support/Code/Cache", .cache),
            Folder("Library/Application Support/Code/CachedData", .cache),
            Folder("Library/Application Support/Code/CachedExtensionVSIXs", .downloads),
        ]),
        Definition(id: "vscodium", name: "VSCodium", systemImage: "curlybraces", appBundleIdentifiers: ["com.vscodium"], folders: [
            Folder("Library/Application Support/VSCodium/Cache", .cache),
            Folder("Library/Application Support/VSCodium/CachedData", .cache),
            Folder("Library/Application Support/VSCodium/CachedExtensionVSIXs", .downloads),
            Folder("Library/Caches/com.vscodium", .cache),
        ]),
        Definition(id: "cursor", name: "Cursor", systemImage: "curlybraces", appBundleIdentifiers: ["com.todesktop.230313mzl4w4u92"], folders: [
            Folder("Library/Application Support/Cursor/Cache", .cache),
            Folder("Library/Application Support/Cursor/CachedData", .cache),
        ]),
        Definition(id: "windsurf", name: "Windsurf & Devin", systemImage: "curlybraces", appBundleIdentifiers: ["com.exafunction.windsurf", "ai.cognition.devin"], folders: [
            Folder("Library/Application Support/Devin/Cache", .cache),
            Folder("Library/Application Support/Devin/CachedData", .cache),
            Folder("Library/Application Support/Windsurf/Cache", .cache),
            Folder("Library/Application Support/Windsurf/CachedData", .cache),
        ]),
        Definition(id: "nova", name: "Nova", systemImage: "curlybraces", appBundleIdentifiers: ["com.panic.Nova"], folders: [
            Folder("Library/Caches/com.panic.Nova", .cache),
        ]),
        Definition(id: "zed", name: "Zed", systemImage: "curlybraces", appBundleIdentifiers: ["dev.zed.Zed"], folders: [
            Folder("Library/Caches/Zed", .cache),
        ]),
        Definition(id: "sublime", name: "Sublime Text", systemImage: "curlybraces", appBundleIdentifiers: ["com.sublimetext.4", "com.sublimetext.3"], folders: [
            Folder("Library/Caches/Sublime Text", .cache),
            Folder("Library/Caches/com.sublimetext.4", .cache),
            Folder("Library/Caches/com.sublimetext.3", .cache),
        ]),
        Definition(id: "androidstudio", name: "Android Studio", systemImage: "curlybraces", appBundleIdentifiers: ["com.google.android.studio"], folders: [
            Folder("Library/Caches/Google/AndroidStudio*/caches", .cache),
            Folder("Library/Caches/Google/AndroidStudio*/index", .cache),
            Folder("Library/Caches/Google/AndroidStudio*/tmp", .cache),
            Folder("Library/Logs/Google/AndroidStudio*", .logs),
        ]),
        Definition(id: "neovim", name: "Neovim", systemImage: "curlybraces", appBundleIdentifiers: [], folders: [
            Folder(".cache/nvim", .cache),
            Folder(".local/share/nvim/lazy", .environments),
            Folder(".local/share/nvim/lazy-rocks", .environments),
            Folder(".local/share/nvim/mason", .environments),
            Folder(".local/state/nvim/lazy", .cache),
        ]),
        // Cloud tools
        Definition(id: "gcloud", name: "Google Cloud CLI", systemImage: "cloud", appBundleIdentifiers: [], folders: [
            Folder(".config/gcloud/logs", .logs),
        ]),
        Definition(id: "azure", name: "Azure CLI", systemImage: "cloud", appBundleIdentifiers: [], folders: [
            Folder(".azure/logs", .logs),
            Folder(".azure/telemetry", .cache),
        ]),
        Definition(id: "kubectl", name: "kubectl", systemImage: "cloud", appBundleIdentifiers: [], folders: [
            Folder(".kube/cache/discovery", .cache),
            Folder(".kube/cache/http", .cache),
        ]),
        Definition(id: "helm", name: "Helm", systemImage: "cloud", appBundleIdentifiers: [], folders: [
            Folder("Library/Caches/helm", .cache),
        ]),
        Definition(id: "githubcli", name: "GitHub CLI", systemImage: "cloud", appBundleIdentifiers: [], folders: [
            Folder(".cache/gh", .cache),
        ]),
        Definition(id: "terraform", name: "Terraform", systemImage: "cloud", appBundleIdentifiers: [], folders: [
            Folder(".terraform.d/plugin-cache", .environments),
        ]),
        Definition(id: "pulumi", name: "Pulumi", systemImage: "cloud", appBundleIdentifiers: [], folders: [
            Folder(".pulumi/plugins", .downloads),
        ]),
        Definition(id: "vercel", name: "Vercel CLI", systemImage: "cloud", appBundleIdentifiers: [], folders: [
            Folder("Library/Caches/com.vercel.cli", .cache),
        ]),
        // Netlify keeps its token in `config.json` in the same folder, so only these two subfolders are listed.
        Definition(id: "netlify", name: "Netlify CLI", systemImage: "cloud", appBundleIdentifiers: [], folders: [
            Folder("Library/Preferences/netlify/deno-cli", .downloads),
            Folder("Library/Preferences/netlify/tunnel", .downloads),
        ]),
        Definition(id: "firebase", name: "Firebase CLI", systemImage: "cloud", appBundleIdentifiers: [], folders: [
            Folder(".cache/firebase", .downloads),
        ]),
        // Build systems and media
        Definition(id: "ccache", name: "ccache", systemImage: "gearshape.2", appBundleIdentifiers: [], folders: [
            Folder("Library/Caches/ccache", .buildData),
            // A legacy `~/.ccache` also holds `ccache.conf` (https://ccache.dev/manual/latest.html), so only
            // the cache's own shards and its temporary folder are named.
            Folder(".ccache/[0-9a-f]", .buildData),
            Folder(".ccache/tmp", .buildData),
        ]),
        Definition(id: "bazel", name: "Bazel", systemImage: "gearshape.2", appBundleIdentifiers: [], folders: [
            Folder("Library/Caches/bazel", .buildData),
            Folder("Library/Caches/bazelisk", .downloads),
        ]),
        Definition(id: "unity", name: "Unity", systemImage: "cube.transparent", appBundleIdentifiers: [], folders: [
            // The Package Manager's cache of downloaded packages: `Library/Unity/cache` up to Unity 2022.3, and
            // `Library/Caches/Unity/upm` from Unity 6 (docs.unity3d.com, Manual/upm-cache.html for each version).
            Folder("Library/Caches/Unity/upm", .downloads),
            Folder("Library/Unity/cache", .downloads),
        ]),
        Definition(id: "blender", name: "Blender", systemImage: "cube.transparent", appBundleIdentifiers: ["org.blenderfoundation.blender"], folders: [
            Folder("Library/Caches/Blender", .cache),
        ]),
        Definition(id: "adobe", name: "Adobe Media Cache", systemImage: "play.rectangle", appBundleIdentifiers: [], folders: [
            Folder("Library/Application Support/Adobe/Common/Media Cache Files", .cache),
            Folder("Library/Application Support/Adobe/Common/Media Cache", .cache),
        ]),
        // Quantum computing. Everything else these SDKs write in the home folder is settings or an account
        // token, so only these three folders are listed.
        Definition(id: "dwave", name: "D-Wave Ocean", systemImage: "atom", appBundleIdentifiers: [], folders: [
            Folder("Library/Caches/dwave-cloud-client", .cache),
        ]),
        Definition(id: "qutip", name: "QuTiP", systemImage: "atom", appBundleIdentifiers: [], folders: [
            Folder(".qutip/qutip_coeffs_*", .buildData),
        ]),
        Definition(id: "qbraid", name: "qBraid", systemImage: "atom", appBundleIdentifiers: [], folders: [
            Folder(".qbraid/environments", .environments),
        ]),

        // Models and datasets
        Definition(id: "ollama", name: "Ollama", systemImage: "brain", appBundleIdentifiers: [], folders: [
            Folder(".ollama/models", .models),
            Folder(".ollama/logs", .logs),
        ]),
        Definition(id: "lmstudio", name: "LM Studio", systemImage: "brain", appBundleIdentifiers: [], folders: [
            Folder(".lmstudio/models", .models),
            Folder(".cache/lm-studio/models", .models),
        ]),
        Definition(id: "huggingface", name: "Hugging Face", systemImage: "brain", appBundleIdentifiers: [], folders: [
            Folder(".cache/huggingface/hub", .models),
            Folder(".cache/huggingface/datasets", .models),
            Folder(".cache/huggingface/xet", .cache),
            Folder(".cache/huggingface/assets", .cache),
            Folder(".cache/huggingface/transformers", .models),
        ]),
        Definition(id: "torch", name: "PyTorch", systemImage: "brain", appBundleIdentifiers: [], folders: [
            Folder(".cache/torch/hub", .models),
            Folder(".cache/torch/transformers", .models),
        ]),
        Definition(id: "mlxdata", name: "MLX Data", systemImage: "brain", appBundleIdentifiers: [], folders: [
            Folder(".cache/mlx.data", .models),
        ]),
        Definition(id: "whisper", name: "Whisper", systemImage: "brain", appBundleIdentifiers: [], folders: [
            Folder(".cache/whisper", .models),
        ]),
        Definition(id: "gpt4all", name: "GPT4All", systemImage: "brain", appBundleIdentifiers: [], folders: [
            Folder(".cache/gpt4all", .models),
        ]),
        Definition(id: "tensorflow", name: "TensorFlow Datasets", systemImage: "brain", appBundleIdentifiers: [], folders: [
            Folder("tensorflow_datasets", .models),
        ]),
        Definition(id: "keras", name: "Keras", systemImage: "brain", appBundleIdentifiers: [], folders: [
            Folder(".keras/datasets", .models),
            Folder(".keras/models", .models),
        ]),
        Definition(id: "nltk", name: "NLTK Data", systemImage: "brain", appBundleIdentifiers: [], folders: [
            Folder("nltk_data", .models),
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
                    for folder in definition.folders {
                        for url in PathPattern.expand(folder.path, home: homeDirectory) {
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
                                kind: folder.kind(at: url),
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
