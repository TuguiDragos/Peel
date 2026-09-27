public import Foundation
import AppKit
internal import PeelPrivileged

public struct DeveloperEnvironment: Sendable, Hashable, Identifiable {
    public enum ContentKind: String, Sendable, Hashable {
        case buildData
        case downloads
        case cache
        /// Logs of what a tool did. Nothing makes them again, and no tool needs them to work.
        case logs
        /// Symbols Xcode copied from a device, which its crash reports need to be read. Most come back only when a
        /// device running that system version connects, and none comes back by itself.
        case deviceSupport
        case archives
        /// Model weights and datasets: large, slow to fetch again.
        case models
        /// Installed sets of packages: virtual environments, editor plug-ins, language servers, and the browsers a test
        /// tool installs, which it does not fetch again by itself.
        case environments
        /// What a tool keeps for the person to install again: installers, store packages, virtual machine boxes.
        case keptDownloads
    }

    public struct Location: Sendable, Hashable, Identifiable {
        public let url: URL
        public let kind: ContentKind
        /// Nil when measuring ran out of time or was refused. Unknown is not the same as empty.
        public let size: Int64?
        /// Where the tool documents the folder.
        public let source: String
        /// True when macOS would not let Peel open the folder, rather than it not answering in time.
        public var couldNotBeRead = false

        public var id: URL { url }

        /// Whether Peel selects this location for the user: only content that tools make or fetch again, or
        /// logs, and only once measured. Nothing is selected for the user without showing its size.
        public var isRecommended: Bool {
            switch kind {
            case .buildData, .downloads, .cache, .logs: size != nil
            case .deviceSupport, .archives, .models, .environments, .keptDownloads: false
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

    /// The name of one of the environment's apps that is running, which is the one to ask the user to quit, or nil
    /// when none runs. Nothing of the environment moves while one runs, from the app or `peel`: it writes in these
    /// folders. Asked each time, since an app can be opened at any moment.
    public var runningApp: String? {
        appBundleIdentifiers.lazy.compactMap { identifier in
            NSRunningApplication.runningApplications(withBundleIdentifier: identifier).lazy.compactMap(\.localizedName).first
        }.first
    }
}

public enum DeveloperCaches {
    struct Definition {
        let id: String
        let name: String
        let systemImage: String
        let appBundleIdentifiers: [String]
        let folders: [Folder]
        /// The tool's own folder inside a folder its vendor shares with other products, such as
        /// `Library/Caches/Google/AndroidStudio*`. Space leaves only that part of the vendor's folder to Developer.
        var ownFolders: [String] = []
    }

    /// A folder a tool keeps, relative to the home folder, and what it holds.
    struct Folder {
        let path: String
        let kind: DeveloperEnvironment.ContentKind
        /// Where the tool documents the folder: a page, or the file inside Xcode that names it.
        let source: String
        /// A store the tool can turn on inside the folder, which projects then link into. While an entry by that
        /// name is there, a link included, the folder is listed without a checkmark: moving it breaks them.
        let storeInside: String?

        init(_ path: String, _ kind: DeveloperEnvironment.ContentKind, source: String, storeInside: String? = nil) {
            self.path = path
            self.kind = kind
            self.source = source
            self.storeInside = storeInside
        }

        /// What the folder at `url` holds now: installed packages once its store is there, `kind` otherwise.
        func kind(at url: URL) -> DeveloperEnvironment.ContentKind {
            guard let storeInside else { return kind }
            let store = url.appending(path: storeInside).path(percentEncoded: false)
            return (try? FileManager.default.attributesOfItem(atPath: store)) != nil ? .environments : kind
        }
    }

    /// The tools' own folders inside `folder`, as the name patterns leading to each (`["Google", "AndroidStudio*"]`),
    /// which Space leaves to the Developer page. Both folders are read as the kernel names them, so another spelling
    /// of the same folder (another case, a link) finds the same.
    static func foldersLeftToDeveloper(inside folder: URL, home: URL) -> [[String]] {
        // Not through `comparablePath`: standardizing drops `/private` only from a path that exists, and most
        // paths in the table don't.
        let base = PathComponents.of(PathPattern.canonical(folder).path(percentEncoded: false))
        let home = PathComponents.of(PathPattern.canonical(home).path(percentEncoded: false))
        let owned = definitions.flatMap { definition in
            let ownFolders = definition.ownFolders.map { home + PathComponents.of($0) }
            return definition.folders.compactMap { folder -> [String]? in
                let full = home + PathComponents.of(folder.path)
                guard full.count > base.count, full.starts(with: base) else { return nil }
                let declared = ownFolders.first { $0.count > base.count && full.starts(with: $0) }
                let own = declared ?? Array(full.prefix(base.count + 1))
                return Array(own[base.count...])
            }
        }
        return Set(owned).sorted { $0.joined(separator: "/") < $1.joined(separator: "/") }
    }

    /// The folders the Developer page offers, relative to the home folder. Only folders one tool owns outright
    /// belong here: no toolchain or installation, nothing holding an account or a token, no path inside another.
    static let definitions: [Definition] = [
        // Apple
        Definition(id: "xcode", name: "Xcode", systemImage: "hammer", appBundleIdentifiers: ["com.apple.dt.Xcode", "com.apple.iphonesimulator"], folders: [
            Folder("Library/Developer/Xcode/DerivedData", .buildData, source: "https://developer.apple.com/documentation/xcode-release-notes/xcode-26-release-notes"),
            Folder("Library/Developer/Xcode/UserData/Previews/Simulator Devices", .buildData, source: "Xcode 27: DVTSystemPrerequisites.framework, beside DVTSimulatorDeviceRemover"),
            Folder("Library/Developer/Xcode/iOS DeviceSupport", .deviceSupport, source: "https://developer.apple.com/documentation/xcode-release-notes/xcode-12_2-release-notes"),
            Folder("Library/Developer/Xcode/watchOS DeviceSupport", .deviceSupport, source: "Xcode 27: CoreSymbolicationDT.framework/Resources/JSONCrashLog/DeviceSupportDirectories.py"),
            Folder("Library/Developer/Xcode/tvOS DeviceSupport", .deviceSupport, source: "Xcode 27: CoreSymbolicationDT.framework/Resources/JSONCrashLog/DeviceSupportDirectories.py"),
            Folder("Library/Developer/Xcode/visionOS DeviceSupport", .deviceSupport, source: "Xcode 27: DVTFoundation.framework (\"%@ DeviceSupport\") and XROS.platform/Info.plist (Description visionOS)"),
            Folder("Library/Developer/Xcode/macOS DeviceSupport", .deviceSupport, source: "Xcode 27: CoreSymbolicationDT.framework/Resources/JSONCrashLog/DeviceSupportDirectories.py"),
            Folder("Library/Developer/CoreSimulator/Caches", .cache, source: "https://developer.apple.com/documentation/xcode-release-notes/xcode-12_3-release-notes"),
            Folder("Library/Caches/com.apple.dt.Xcode", .cache, source: "https://developer.apple.com/documentation/foundation/filemanager/searchpathdirectory/cachesdirectory"),
            Folder("Library/Developer/Packages", .keptDownloads, source: "https://developer.apple.com/documentation/xcode-release-notes/xcode-16_2-release-notes"),
            Folder("Library/Developer/Xcode/Archives", .archives, source: "Xcode 27: IDEFoundation.framework, -[IDEDeveloperPaths defaultDistributionArchivesLocation]"),
        ]),
        Definition(id: "swiftpm", name: "Swift Package Manager", systemImage: "swift", appBundleIdentifiers: [], folders: [
            Folder("Library/Caches/org.swift.swiftpm", .downloads, source: "https://github.com/swiftlang/swift-package-manager/blob/main/Sources/Basics/FileSystem/FileSystem+Extensions.swift#L246-L253"),
        ]),
        Definition(id: "cocoapods", name: "CocoaPods", systemImage: "shippingbox", appBundleIdentifiers: [], folders: [
            Folder("Library/Caches/CocoaPods", .downloads, source: "https://github.com/CocoaPods/CocoaPods/blob/master/lib/cocoapods/config.rb#L23"),
            // The CDN copy of the public spec index. The spec repositories a person added sit beside it and stay.
            Folder(".cocoapods/repos/trunk", .cache, source: "https://github.com/CocoaPods/Core/blob/master/lib/cocoapods-core/trunk_source.rb#L2-L7"),
        ]),
        Definition(id: "carthage", name: "Carthage", systemImage: "shippingbox", appBundleIdentifiers: [], folders: [
            Folder("Library/Caches/org.carthage.CarthageKit", .downloads, source: "https://github.com/Carthage/Carthage/blob/master/Source/CarthageKit/Constants.swift#L31"),
        ]),
        Definition(id: "homebrew", name: "Homebrew", systemImage: "mug", appBundleIdentifiers: [], folders: [
            Folder("Library/Caches/Homebrew/downloads", .downloads, source: "https://github.com/Homebrew/brew/blob/main/Library/Homebrew/download_strategy/abstract_file_download_strategy.rb#L42"),
            Folder("Library/Caches/Homebrew/Cask", .downloads, source: "https://github.com/Homebrew/brew/blob/main/Library/Homebrew/cask/cache.rb#L9"),
            Folder("Library/Caches/Homebrew/bootsnap", .cache, source: "https://github.com/Homebrew/brew/blob/main/Library/Homebrew/startup/bootsnap.rb#L45"),
            Folder("Library/Caches/Homebrew/*_cache", .cache, source: "https://github.com/Homebrew/brew/blob/main/Library/Homebrew/package_manager_cache.rb#L5-L27"),
            Folder("Library/Logs/Homebrew", .logs, source: "https://github.com/Homebrew/brew/blob/main/Library/Homebrew/utils/os.sh#L55-L56"),
        ]),
        Definition(id: "swiftlint", name: "SwiftLint", systemImage: "swift", appBundleIdentifiers: [], folders: [
            Folder("Library/Caches/SwiftLint", .cache, source: "https://github.com/realm/SwiftLint/blob/main/Source/SwiftLintFramework/Configuration/Configuration+Cache.swift#L80-L85"),
        ]),
        Definition(id: "tuist", name: "Tuist", systemImage: "hammer", appBundleIdentifiers: [], folders: [
            Folder(".cache/tuist", .buildData, source: "https://github.com/tuist/tuist/blob/main/server/priv/docs/en/cli/directories.md"),
        ]),
        // JavaScript
        Definition(id: "npm", name: "npm", systemImage: "cube", appBundleIdentifiers: [], folders: [
            Folder(".npm/_cacache", .downloads, source: "https://github.com/npm/cli/blob/latest/workspaces/config/lib/definitions/definitions.js#L443"),
            Folder(".npm/_npx", .downloads, source: "https://github.com/npm/cli/blob/latest/workspaces/config/lib/definitions/definitions.js#L444"),
            Folder(".npm/_logs", .logs, source: "https://github.com/npm/cli/blob/latest/workspaces/config/lib/definitions/definitions.js#L1481-L1486"),
        ]),
        Definition(id: "yarn", name: "Yarn", systemImage: "cube", appBundleIdentifiers: [], folders: [
            Folder("Library/Caches/Yarn", .downloads, source: "https://github.com/yarnpkg/yarn/blob/master/src/util/user-dirs.js#L32-L33"),
            // Yarn's Plug'n'Play projects load every package from this cache, so it is listed and never selected:
            // moving it breaks each such project until `yarn install` runs in it again.
            Folder(".yarn/berry/cache", .environments, source: "https://github.com/yarnpkg/berry/blob/master/packages/yarnpkg-core/sources/Configuration.ts"),
            Folder(".yarn/berry/metadata", .cache, source: "https://github.com/yarnpkg/berry/blob/master/packages/plugin-npm/sources/npmHttpUtils.ts#L317"),
        ]),
        Definition(id: "pnpm", name: "pnpm", systemImage: "cube", appBundleIdentifiers: [], folders: [
            Folder("Library/pnpm/store", .environments, source: "https://github.com/pnpm/pnpm.io/blob/main/docs/settings/store.md#L15"),
            Folder("Library/Caches/pnpm", .cache, source: "https://github.com/pnpm/pnpm.io/blob/main/docs/settings/other.md#L175"),
        ]),
        Definition(id: "bun", name: "Bun", systemImage: "cube", appBundleIdentifiers: [], folders: [
            // Bun's global virtual store, once turned on, is `links`, and every project's `node_modules` then points
            // into it (Bun's documentation, "Global virtual store").
            Folder(".bun/install/cache", .downloads, source: "https://github.com/oven-sh/bun/blob/main/docs/pm/global-store.mdx", storeInside: "links"),
            Folder("Library/Caches/bun", .cache, source: "https://github.com/oven-sh/bun/blob/main/src/jsc/RuntimeTranspilerCache.rs#L657-L660"),
        ]),
        Definition(id: "deno", name: "Deno", systemImage: "chevron.left.forwardslash.chevron.right", appBundleIdentifiers: [], folders: [
            // `DENO_DIR` keeps the REPL history (`deno_history.txt`) and what scripts store (`location_data`)
            // beside its caches, so the caches are named one by one, as Deno's `deno_dir.rs` names them. `deps` and
            // the `_v1` databases are Deno 1's names.
            Folder("Library/Caches/deno/remote", .downloads, source: "https://github.com/denoland/deno/blob/main/libs/resolver/cache/deno_dir.rs"),
            Folder("Library/Caches/deno/deps", .downloads, source: "https://github.com/denoland/deno/blob/v1.46.3/cli/cache/deno_dir.rs"),
            Folder("Library/Caches/deno/npm", .downloads, source: "https://github.com/denoland/deno/blob/main/libs/resolver/cache/deno_dir.rs"),
            Folder("Library/Caches/deno/dl", .downloads, source: "https://github.com/denoland/deno/blob/main/libs/resolver/cache/deno_dir.rs"),
            Folder("Library/Caches/deno/gen", .buildData, source: "https://github.com/denoland/deno/blob/main/libs/resolver/cache/deno_dir.rs"),
            Folder("Library/Caches/deno/registries", .cache, source: "https://github.com/denoland/deno/blob/main/libs/resolver/cache/deno_dir.rs"),
            Folder("Library/Caches/deno/*_cache_v1", .cache, source: "https://github.com/denoland/deno/blob/v1.40.0/cli/cache/deno_dir.rs"),
            Folder("Library/Caches/deno/*_cache_v2", .cache, source: "https://github.com/denoland/deno/blob/main/libs/resolver/cache/deno_dir.rs"),
        ]),
        Definition(id: "reactnative", name: "React Native CLI", systemImage: "cube", appBundleIdentifiers: [], folders: [
            Folder("Library/Caches/react-native-cli", .cache, source: "https://github.com/react-native-community/cli/blob/main/packages/cli-tools/src/cacheManager.ts#L49-L50"),
        ]),
        Definition(id: "expo", name: "Expo", systemImage: "cube", appBundleIdentifiers: [], folders: [
            Folder(".expo/expo-go", .downloads, source: "https://github.com/expo/expo/blob/main/packages/@expo/cli/src/utils/downloadExpoGoAsync.ts#L128-L129"),
            Folder(".expo/versions-cache", .cache, source: "https://github.com/expo/expo/blob/main/packages/@expo/cli/src/api/getVersions.ts#L47"),
            Folder(".expo/ios-simulator-app-cache", .downloads, source: "https://github.com/expo/expo/blob/main/packages/@expo/cli/src/utils/downloadExpoGoAsync.ts#L21"),
            Folder(".expo/android-apk-cache", .downloads, source: "https://github.com/expo/expo/blob/main/packages/@expo/cli/src/utils/downloadExpoGoAsync.ts#L27"),
            Folder(".expo/schema-cache", .cache, source: "https://github.com/expo/expo/blob/main/packages/@expo/cli/src/api/getExpoSchema.ts#L83"),
            Folder(".expo/native-modules-cache", .cache, source: "https://github.com/expo/expo/blob/main/packages/@expo/cli/src/api/getNativeModuleVersions.ts#L35"),
        ]),
        Definition(id: "nx", name: "Nx", systemImage: "cube", appBundleIdentifiers: [], folders: [
            // One workspace's `cache` and `databases`, named by 16 hex digits of a hash. They go together: Nx
            // answers a cache hit from the database alone, and a database without its cache restores nothing.
            Folder(".nx/" + String(repeating: "[0-9a-f]", count: 16), .buildData, source: "https://github.com/nrwl/nx/blob/master/packages/nx/src/utils/cache-directory.ts"),
        ]),
        // The package manager versions Corepack downloaded, and not `lastKnownGood.json` beside them, which holds
        // the ones a person chose.
        Definition(id: "corepack", name: "Corepack", systemImage: "cube", appBundleIdentifiers: [], folders: [
            Folder(".cache/node/corepack/v1", .downloads, source: "https://github.com/nodejs/corepack/blob/main/sources/folderUtils.ts"),
        ]),
        Definition(id: "nvm", name: "nvm", systemImage: "cube", appBundleIdentifiers: [], folders: [
            Folder(".nvm/.cache", .downloads, source: "https://github.com/nvm-sh/nvm/blob/master/nvm.sh#L3337-L3338"),
        ]),
        Definition(id: "prisma", name: "Prisma", systemImage: "cube", appBundleIdentifiers: [], folders: [
            Folder(".cache/prisma", .downloads, source: "https://github.com/prisma/prisma/blob/7.10.0/packages/fetch-engine/src/utils.ts#L38-L40"),
        ]),
        Definition(id: "playwright", name: "Playwright", systemImage: "globe", appBundleIdentifiers: [], folders: [
            Folder("Library/Caches/ms-playwright", .environments, source: "https://github.com/microsoft/playwright/blob/main/docs/src/browsers.md#L958"),
        ]),
        Definition(id: "playwrightgo", name: "Playwright for Go", systemImage: "globe", appBundleIdentifiers: [], folders: [
            Folder("Library/Caches/ms-playwright-go", .environments, source: "https://github.com/playwright-community/playwright-go/blob/main/run.go#L370-L372"),
        ]),
        // The drivers and browsers Selenium Manager keeps, and not `se-config.toml`, its settings, beside them.
        Definition(id: "selenium", name: "Selenium Manager", systemImage: "globe", appBundleIdentifiers: [], folders: [
            Folder(".cache/selenium/*/", .downloads, source: "https://github.com/SeleniumHQ/seleniumhq.github.io/blob/trunk/website_and_docs/content/documentation/selenium_manager.en.md#L34"),
        ]),
        Definition(id: "cypress", name: "Cypress", systemImage: "globe", appBundleIdentifiers: [], folders: [
            Folder("Library/Caches/Cypress", .environments, source: "https://github.com/cypress-io/cypress-documentation/blob/main/docs/app/get-started/advanced-installation.mdx#L615"),
        ]),
        Definition(id: "puppeteer", name: "Puppeteer", systemImage: "globe", appBundleIdentifiers: [], folders: [
            Folder(".cache/puppeteer", .environments, source: "https://github.com/puppeteer/puppeteer/blob/main/packages/puppeteer/src/getConfiguration.ts#L162-L165"),
        ]),
        Definition(id: "electron", name: "Electron", systemImage: "cube", appBundleIdentifiers: [], folders: [
            Folder("Library/Caches/electron", .downloads, source: "https://github.com/electron/get/blob/main/README.md#L123"),
            Folder("Library/Caches/electron-builder", .downloads, source: "https://github.com/electron-userland/electron-builder/blob/master/website/docs/environment-variables.md#L166"),
            Folder(".electron-gyp", .downloads, source: "https://github.com/electron/rebuild/blob/main/src/constants.ts#L4"),
        ]),
        Definition(id: "nodegyp", name: "node-gyp", systemImage: "cube", appBundleIdentifiers: [], folders: [
            Folder("Library/Caches/node-gyp", .downloads, source: "https://github.com/nodejs/node-gyp/blob/main/bin/node-gyp.js#L25"),
            Folder(".node-gyp", .downloads, source: "https://github.com/nodejs/node-gyp/blob/main/CHANGELOG.md#v500-2019-06-13"),
        ]),
        Definition(id: "typescript", name: "TypeScript", systemImage: "cube", appBundleIdentifiers: [], folders: [
            Folder("Library/Caches/typescript", .downloads, source: "https://github.com/microsoft/TypeScript/blob/main/tsc/internal/vfs/osvfs/os.go#L193-L206"),
        ]),
        // Python
        Definition(id: "pip", name: "pip", systemImage: "chevron.left.forwardslash.chevron.right", appBundleIdentifiers: [], folders: [
            Folder("Library/Caches/pip", .downloads, source: "https://github.com/pypa/pip/blob/main/docs/html/topics/caching.md#L84-L88"),
        ]),
        Definition(id: "poetry", name: "Poetry", systemImage: "chevron.left.forwardslash.chevron.right", appBundleIdentifiers: [], folders: [
            Folder("Library/Caches/pypoetry/cache", .downloads, source: "https://github.com/python-poetry/poetry/blob/main/src/poetry/config/config.py#L283-L284"),
            Folder("Library/Caches/pypoetry/artifacts", .downloads, source: "https://github.com/python-poetry/poetry/blob/main/src/poetry/config/config.py#L287-L288"),
            Folder("Library/Caches/pypoetry/virtualenvs", .environments, source: "https://github.com/python-poetry/poetry/blob/main/docs/configuration.md#L613-L617"),
        ]),
        Definition(id: "uv", name: "uv", systemImage: "chevron.left.forwardslash.chevron.right", appBundleIdentifiers: [], folders: [
            Folder(".cache/uv", .environments, source: "https://github.com/astral-sh/uv/blob/main/docs/concepts/cache.md#L193-L194"),
        ]),
        Definition(id: "precommit", name: "pre-commit", systemImage: "chevron.left.forwardslash.chevron.right", appBundleIdentifiers: [], folders: [
            Folder(".cache/pre-commit", .cache, source: "https://github.com/pre-commit/pre-commit.com/blob/main/sections/advanced.md#L773"),
        ]),
        Definition(id: "pipenv", name: "Pipenv", systemImage: "chevron.left.forwardslash.chevron.right", appBundleIdentifiers: [], folders: [
            Folder("Library/Caches/pipenv", .downloads, source: "https://github.com/pypa/pipenv/blob/main/pipenv/environments.py#L109-L110"),
            Folder(".local/share/virtualenvs", .environments, source: "https://github.com/pypa/pipenv/blob/main/docs/virtualenv.md#L25"),
        ]),
        Definition(id: "virtualenvwrapper", name: "virtualenvwrapper", systemImage: "chevron.left.forwardslash.chevron.right", appBundleIdentifiers: [], folders: [
            // The environments, not the hook scripts virtualenvwrapper keeps beside them: a pattern that ends in `/`
            // matches folders only.
            Folder(".virtualenvs/*/", .environments, source: "https://github.com/python-virtualenvwrapper/virtualenvwrapper/blob/main/docs/source/install.rst"),
        ]),
        Definition(id: "conda", name: "Conda", systemImage: "chevron.left.forwardslash.chevron.right", appBundleIdentifiers: [], folders: [
            Folder("miniconda3/pkgs", .environments, source: "https://www.anaconda.com/docs/getting-started/miniconda/install/mac-cli-install"),
            Folder("anaconda3/pkgs", .environments, source: "https://www.anaconda.com/docs/getting-started/anaconda/install/mac-cli-install"),
            Folder(".conda/pkgs", .environments, source: "https://github.com/conda/conda/blob/main/conda/base/context.py#L834-L847"),
            Folder("miniforge3/pkgs", .environments, source: "https://github.com/conda-forge/miniforge/blob/main/README.md#L53"),
        ]),
        Definition(id: "mamba", name: "mamba & micromamba", systemImage: "chevron.left.forwardslash.chevron.right", appBundleIdentifiers: [], folders: [
            Folder("micromamba/pkgs", .environments, source: "https://github.com/mamba-org/mamba/blob/main/libmamba/src/api/configuration.cpp#L1011-L1015"),
            Folder(".mamba/pkgs", .environments, source: "https://github.com/mamba-org/mamba/blob/main/libmamba/src/api/configuration.cpp#L1015"),
        ]),
        Definition(id: "pixi", name: "pixi", systemImage: "chevron.left.forwardslash.chevron.right", appBundleIdentifiers: [], folders: [
            Folder("Library/Caches/rattler", .downloads, source: "https://github.com/prefix-dev/pixi/blob/main/docs/workspace/environment.md#L171-L179"),
        ]),
        Definition(id: "pdm", name: "PDM", systemImage: "chevron.left.forwardslash.chevron.right", appBundleIdentifiers: [], folders: [
            Folder("Library/Caches/pdm/http", .cache, source: "https://github.com/pdm-project/pdm/blob/main/src/pdm/environments/base.py#L140"),
            Folder("Library/Caches/pdm/wheels", .downloads, source: "https://github.com/pdm-project/pdm/blob/main/src/pdm/project/core.py#L912-L944"),
            Folder("Library/Caches/pdm/metadata", .cache, source: "https://github.com/pdm-project/pdm/blob/main/src/pdm/project/core.py#L912-L944"),
            Folder("Library/Caches/pdm/hashes", .cache, source: "https://github.com/pdm-project/pdm/blob/main/src/pdm/project/core.py#L912-L944"),
            // PDM's `packages` is the store projects link their installed packages into, so it is never selected.
            Folder("Library/Caches/pdm/packages", .environments, source: "https://github.com/pdm-project/pdm/blob/main/docs/usage/config.md#L252"),
            Folder("Library/Logs/pdm", .logs, source: "https://github.com/pdm-project/pdm/blob/main/src/pdm/project/config.py#L116-L120"),
        ]),
        Definition(id: "hatch", name: "Hatch", systemImage: "chevron.left.forwardslash.chevron.right", appBundleIdentifiers: [], folders: [
            Folder("Library/Caches/hatch", .cache, source: "https://github.com/pypa/hatch/blob/master/docs/config/hatch.md#L140-L146"),
        ]),
        Definition(id: "pipx", name: "pipx", systemImage: "chevron.left.forwardslash.chevron.right", appBundleIdentifiers: [], folders: [
            Folder("Library/Caches/pipx", .cache, source: "https://github.com/pypa/pipx/blob/main/src/pipx/paths.py#L76-L77"),
            Folder("Library/Logs/pipx", .logs, source: "https://github.com/pypa/pipx/blob/main/src/pipx/paths.py#L126"),
        ]),
        Definition(id: "piptools", name: "pip-tools", systemImage: "chevron.left.forwardslash.chevron.right", appBundleIdentifiers: [], folders: [
            Folder("Library/Caches/pip-tools", .cache, source: "https://github.com/jazzband/pip-tools/blob/main/piptools/locations.py#L5-L6"),
        ]),
        Definition(id: "black", name: "Black", systemImage: "chevron.left.forwardslash.chevron.right", appBundleIdentifiers: [], folders: [
            Folder("Library/Caches/black", .cache, source: "https://github.com/psf/black/blob/main/src/black/cache.py#L42-L43"),
        ]),
        Definition(id: "jedi", name: "Jedi & Parso", systemImage: "chevron.left.forwardslash.chevron.right", appBundleIdentifiers: [], folders: [
            Folder("Library/Caches/Jedi", .cache, source: "https://github.com/davidhalter/jedi/blob/master/jedi/settings.py#L77-L78"),
            Folder("Library/Caches/Parso", .cache, source: "https://github.com/davidhalter/parso/blob/master/parso/cache.py#L69-L70"),
        ]),
        // Rust and Go
        Definition(id: "cargo", name: "Cargo", systemImage: "gearshape.2", appBundleIdentifiers: [], folders: [
            Folder(".cargo/registry/cache", .downloads, source: "https://github.com/rust-lang/cargo/blob/master/doc/book/src/guide/cargo-home.md#L47-L48"),
            Folder(".cargo/registry/index", .downloads, source: "https://github.com/rust-lang/cargo/blob/master/doc/book/src/guide/cargo-home.md#L44-L45"),
            Folder(".cargo/registry/src", .downloads, source: "https://github.com/rust-lang/cargo/blob/master/doc/book/src/guide/cargo-home.md#L50-L51"),
            Folder(".cargo/git/checkouts", .downloads, source: "https://github.com/rust-lang/cargo/blob/master/doc/book/src/guide/cargo-home.md#L36-L37"),
            Folder(".cargo/git/db", .downloads, source: "https://github.com/rust-lang/cargo/blob/master/doc/book/src/guide/cargo-home.md#L33-L34"),
        ]),
        Definition(id: "go", name: "Go", systemImage: "chevron.left.forwardslash.chevron.right", appBundleIdentifiers: [], folders: [
            Folder("Library/Caches/go-build", .buildData, source: "https://github.com/golang/go/blob/master/src/cmd/go/alldocs.go#L2372-L2373"),
            Folder("go/pkg/mod/cache/download", .downloads, source: "https://github.com/golang/website/blob/master/_content/ref/mod.md#L4020-L4028"),
            Folder("go/pkg/mod/cache/vcs", .downloads, source: "https://github.com/golang/website/blob/master/_content/ref/mod.md#L4088-L4095"),
        ]),
        Definition(id: "sccache", name: "sccache", systemImage: "gearshape.2", appBundleIdentifiers: [], folders: [
            Folder("Library/Caches/Mozilla.sccache", .buildData, source: "https://github.com/mozilla/sccache/blob/main/docs/Local.md#L3"),
        ]),
        Definition(id: "gopls", name: "gopls", systemImage: "chevron.left.forwardslash.chevron.right", appBundleIdentifiers: [], folders: [
            Folder("Library/Caches/gopls", .cache, source: "https://github.com/golang/tools/blob/master/gopls/internal/filecache/filecache.go#L430-L438"),
        ]),
        Definition(id: "golangcilint", name: "golangci-lint", systemImage: "chevron.left.forwardslash.chevron.right", appBundleIdentifiers: [], folders: [
            Folder("Library/Caches/golangci-lint", .cache, source: "https://github.com/golangci/golangci-lint/blob/main/docs/content/docs/configuration/cli.md#L63"),
        ]),
        Definition(id: "staticcheck", name: "Staticcheck", systemImage: "chevron.left.forwardslash.chevron.right", appBundleIdentifiers: [], folders: [
            Folder("Library/Caches/staticcheck", .cache, source: "https://github.com/dominikh/go-tools/blob/master/lintcmd/cache/default.go#L80-L85"),
        ]),
        // JVM and Android
        Definition(id: "gradle", name: "Gradle", systemImage: "cup.and.saucer", appBundleIdentifiers: [], folders: [
            Folder(".gradle/caches", .downloads, source: "https://github.com/gradle/gradle/blob/master/platforms/documentation/docs/src/docs/userguide/reference/runtime-configuration/directory_layout.adoc#L40-L53"),
            Folder(".gradle/wrapper/dists", .downloads, source: "https://github.com/gradle/gradle/blob/master/platforms/documentation/docs/src/docs/userguide/reference/runtime-configuration/directory_layout.adoc#L52"),
            Folder(".gradle/daemon", .cache, source: "https://github.com/gradle/gradle/blob/master/platforms/documentation/docs/src/docs/userguide/reference/runtime-configuration/directory_layout.adoc#L49"),
        ]),
        Definition(id: "maven", name: "Maven", systemImage: "cup.and.saucer", appBundleIdentifiers: [], folders: [
            Folder(".m2/repository", .environments, source: "https://github.com/apache/maven/blob/master/api/maven-api-settings/src/main/mdo/settings.mdo#L110"),
            Folder(".m2/wrapper/dists", .downloads, source: "https://github.com/apache/maven-wrapper/blob/master/maven-wrapper/src/site/markdown/index.md#L29"),
        ]),
        Definition(id: "sbt", name: "sbt & Coursier", systemImage: "cup.and.saucer", appBundleIdentifiers: [], folders: [
            Folder(".sbt/boot", .downloads, source: "https://github.com/sbt/website/blob/develop/src/reference/01-Faq/00.md#L283-L284"),
            Folder(".ivy2/cache", .downloads, source: "https://github.com/apache/ant-ivy/blob/master/asciidoc/settings/caches.adoc#L48"),
            // Only the cache. `Coursier/jvm` beside it holds the JVMs `cs java` installed, which `JAVA_HOME`
            // points at (https://get-coursier.io/docs/cache and https://get-coursier.io/docs/cli-java).
            Folder("Library/Caches/Coursier/v1", .downloads, source: "https://github.com/coursier/coursier/blob/main/doc/docs/cache.md#L30"),
            Folder(".coursier/cache/v1", .downloads, source: "https://github.com/coursier/coursier/blob/main/doc/docs/cache.md#L48-L54"),
            Folder("Library/Caches/sbt", .buildData, source: "https://github.com/sbt/sbt/blob/develop/main/src/main/scala/sbt/internal/SysProp.scala#L231-L245"),
        ]),
        Definition(id: "konan", name: "Kotlin/Native", systemImage: "cup.and.saucer", appBundleIdentifiers: [], folders: [
            Folder(".konan/dependencies", .downloads, source: "https://github.com/JetBrains/kotlin/blob/master/native/utils/src/org/jetbrains/kotlin/konan/util/DependencyDirectories.kt#L12-L32"),
            Folder(".konan/cache", .buildData, source: "https://github.com/JetBrains/kotlin/blob/master/native/utils/src/org/jetbrains/kotlin/konan/util/DependencyDirectories.kt#L13-L36"),
        ]),
        // Other languages
        Definition(id: "dart", name: "Dart & Flutter", systemImage: "chevron.left.forwardslash.chevron.right", appBundleIdentifiers: [], folders: [
            Folder(".pub-cache/hosted", .downloads, source: "https://github.com/dart-lang/site-www/blob/main/src/content/tools/pub/cmd/pub-get.md#L99-L100"),
            Folder(".pub-cache/git", .downloads, source: "https://github.com/dart-lang/pub/blob/main/lib/src/system_cache.dart#L48"),
            Folder(".dartServer/.analysis-driver", .cache, source: "https://github.com/dart-lang/sdk/blob/main/pkg/analysis_server/lib/src/analysis_server.dart#L737-L741"),
        ]),
        Definition(id: "composer", name: "Composer", systemImage: "chevron.left.forwardslash.chevron.right", appBundleIdentifiers: [], folders: [
            Folder("Library/Caches/composer", .downloads, source: "https://github.com/composer/composer/blob/main/doc/06-config.md#L1105-L1108"),
            Folder(".composer/cache", .downloads, source: "https://github.com/composer/composer/blob/main/src/Composer/Factory.php#L122-L128"),
        ]),
        Definition(id: "rubygems", name: "RubyGems & Bundler", systemImage: "shippingbox", appBundleIdentifiers: [], folders: [
            Folder(".gem/ruby/*/cache", .downloads, source: "https://github.com/ruby/rubygems/blob/master/lib/rubygems/specification.rb#L1659-L1660"),
            Folder(".gem/specs", .cache, source: "https://github.com/ruby/rubygems/blob/master/lib/rubygems/defaults.rb#L23-L30"),
            Folder(".cache/gem/gems", .downloads, source: "https://github.com/ruby/rubygems/blob/master/lib/rubygems/defaults.rb#L151-L158"),
            Folder(".cache/gem/specs", .cache, source: "https://github.com/ruby/rubygems/blob/master/lib/rubygems/defaults.rb#L26-L28"),
            Folder(".bundle/cache", .downloads, source: "https://github.com/ruby/rubygems/blob/master/lib/bundler.rb#L284-L303"),
            Folder(".local/share/gem/ruby/*/cache", .downloads, source: "https://github.com/ruby/rubygems/blob/master/lib/rubygems/defaults.rb#L103-L109"),
        ]),
        Definition(id: "nuget", name: "NuGet", systemImage: "shippingbox", appBundleIdentifiers: [], folders: [
            Folder(".nuget/packages", .downloads, source: "https://github.com/NuGet/docs.microsoft.com-nuget/blob/main/docs/consume-packages/managing-the-global-packages-and-cache-folders.md#L17"),
            Folder(".local/share/NuGet/v3-cache", .cache, source: "https://github.com/NuGet/docs.microsoft.com-nuget/blob/main/docs/consume-packages/managing-the-global-packages-and-cache-folders.md#L18"),
            Folder(".local/share/NuGet/plugins-cache", .cache, source: "https://github.com/NuGet/docs.microsoft.com-nuget/blob/main/docs/consume-packages/managing-the-global-packages-and-cache-folders.md#L20"),
        ]),
        Definition(id: "julia", name: "Julia", systemImage: "chevron.left.forwardslash.chevron.right", appBundleIdentifiers: [], folders: [
            Folder(".julia/artifacts", .downloads, source: "https://github.com/JuliaLang/julia/blob/master/base/initdefs.jl#L111"),
            Folder(".julia/clones", .downloads, source: "https://github.com/JuliaLang/julia/blob/master/base/initdefs.jl#L112"),
            Folder(".julia/compiled", .buildData, source: "https://github.com/JuliaLang/julia/blob/master/base/initdefs.jl#L114"),
            Folder(".julia/scratchspaces", .cache, source: "https://github.com/JuliaLang/julia/blob/master/base/initdefs.jl#L120"),
        ]),
        Definition(id: "nix", name: "Nix", systemImage: "shippingbox", appBundleIdentifiers: [], folders: [
            Folder(".cache/nix", .cache, source: "https://github.com/NixOS/nix/blob/master/src/libutil/include/nix/util/users.hh#L28-L30"),
        ]),
        Definition(id: "rubocop", name: "RuboCop", systemImage: "chevron.left.forwardslash.chevron.right", appBundleIdentifiers: [], folders: [
            Folder(".cache/rubocop_cache", .cache, source: "https://github.com/rubocop/rubocop/blob/master/lib/rubocop/cache_config.rb#L23-L26"),
        ]),
        Definition(id: "hex", name: "Hex", systemImage: "shippingbox", appBundleIdentifiers: [], folders: [
            Folder(".hex/packages", .downloads, source: "https://github.com/hexpm/hex/blob/main/lib/hex/scm.ex#L8"),
        ]),
        Definition(id: "rebar3", name: "rebar3", systemImage: "shippingbox", appBundleIdentifiers: [], folders: [
            Folder(".cache/rebar3/hex", .downloads, source: "https://github.com/erlang/rebar3/blob/main/apps/rebar/src/rebar_packages.erl#L159-L160"),
        ]),
        Definition(id: "gleam", name: "Gleam", systemImage: "shippingbox", appBundleIdentifiers: [], folders: [
            Folder("Library/Caches/gleam/hex/hexpm/packages", .downloads, source: "https://github.com/gleam-lang/gleam/blob/main/compiler-core/src/paths.rs#L171-L183"),
        ]),
        Definition(id: "cabal", name: "Cabal", systemImage: "shippingbox", appBundleIdentifiers: [], folders: [
            Folder(".cache/cabal", .downloads, source: "https://github.com/haskell/cabal/blob/master/doc/config.rst#L112-L115"),
        ]),
        Definition(id: "stack", name: "Haskell Stack", systemImage: "shippingbox", appBundleIdentifiers: [], folders: [
            Folder(".stack/pantry/hackage", .downloads, source: "https://github.com/commercialhaskell/stack/blob/master/doc/topics/stack_root.md#L228-L232"),
            Folder(".stack/setup-exe-cache", .buildData, source: "https://github.com/commercialhaskell/stack/blob/master/doc/topics/stack_root.md#L279-L285"),
        ]),
        Definition(id: "opam", name: "opam", systemImage: "shippingbox", appBundleIdentifiers: [], folders: [
            Folder(".opam/download-cache", .downloads, source: "https://github.com/ocaml/opam/blob/master/doc/pages/Manual.md#L41"),
        ]),
        Definition(id: "luarocks", name: "LuaRocks", systemImage: "shippingbox", appBundleIdentifiers: [], folders: [
            Folder(".cache/luarocks", .downloads, source: "https://github.com/luarocks/luarocks/blob/main/src/luarocks/core/cfg.lua#L411-L412"),
        ]),
        Definition(id: "renv", name: "renv", systemImage: "shippingbox", appBundleIdentifiers: [], folders: [
            // renv links each project's library into this cache, so it is never selected.
            Folder("Library/Caches/org.R-project.R/R/renv/cache", .environments, source: "https://github.com/rstudio/renv/blob/main/vignettes/package-install.Rmd#L56"),
        ]),
        Definition(id: "clojure", name: "Clojure", systemImage: "chevron.left.forwardslash.chevron.right", appBundleIdentifiers: [], folders: [
            Folder(".gitlibs", .downloads, source: "https://github.com/clojure/tools.gitlibs/blob/master/README.md#L44"),
        ]),
        Definition(id: "mise", name: "mise", systemImage: "shippingbox", appBundleIdentifiers: [], folders: [
            Folder("Library/Caches/mise", .cache, source: "https://github.com/jdx/mise/blob/main/docs/directories.md#L34-L41"),
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
            Folder("Library/Caches/JetBrains/*/caches", .cache, source: "https://github.com/JetBrains/intellij-community/blob/master/platform/platform-impl/src/com/intellij/openapi/vfs/newvfs/persistent/FSRecords.java#L80"),
            Folder("Library/Caches/JetBrains/*/index", .cache, source: "https://github.com/JetBrains/intellij-community/blob/master/platform/util/src/com/intellij/openapi/application/PathManager.java#L648-L651"),
            Folder("Library/Caches/JetBrains/*/tmp", .cache, source: "https://github.com/JetBrains/intellij-community/blob/master/platform/util/src/com/intellij/openapi/application/PathManager.java#L634-L636"),
            Folder("Library/Logs/JetBrains", .logs, source: "https://www.jetbrains.com/help/idea/directories-used-by-the-ide-to-store-settings-caches-plugins-and-logs.html"),
        ]),
        Definition(id: "vscode", name: "Visual Studio Code", systemImage: "curlybraces", appBundleIdentifiers: ["com.microsoft.VSCode"], folders: [
            Folder("Library/Application Support/Code/Cache", .cache, source: "https://github.com/electron/electron/blob/main/shell/browser/net/network_context_service.cc#L94-L95"),
            Folder("Library/Application Support/Code/CachedData", .cache, source: "https://github.com/microsoft/vscode/blob/main/src/main.ts#L648-L666"),
            Folder("Library/Application Support/Code/CachedExtensionVSIXs", .downloads, source: "https://github.com/microsoft/vscode/blob/main/src/vs/platform/environment/common/environmentService.ts#L127"),
            Folder("Library/Application Support/Code/logs", .logs, source: "https://github.com/microsoft/vscode/blob/main/src/vs/platform/environment/common/environmentService.ts#L73-L79"),
            Folder("Library/Application Support/Code/Code Cache", .cache, source: "https://github.com/chromium/chromium/blob/main/content/browser/storage_partition_impl.cc#L1585"),
            Folder("Library/Application Support/Code/GPUCache", .cache, source: "https://github.com/chromium/chromium/blob/main/gpu/ipc/common/gpu_disk_cache_type.cc#L46"),
            Folder("Library/Application Support/Code/DawnWebGPUCache", .cache, source: "https://github.com/chromium/chromium/blob/main/gpu/ipc/common/gpu_disk_cache_type.cc#L48"),
            Folder("Library/Application Support/Code/DawnGraphiteCache", .cache, source: "https://github.com/chromium/chromium/blob/main/gpu/ipc/common/gpu_disk_cache_type.cc#L50"),
            Folder("Library/Application Support/Code/CachedProfilesData", .cache, source: "https://github.com/microsoft/vscode/blob/main/src/vs/platform/userDataProfile/common/userDataProfile.ts#L274"),
            Folder("Library/Caches/com.microsoft.VSCode.ShipIt", .downloads, source: "https://github.com/Squirrel/Squirrel.Mac/blob/main/Squirrel/SQRLUpdater.m#L814-L829"),
        ]),
        Definition(id: "vscodium", name: "VSCodium", systemImage: "curlybraces", appBundleIdentifiers: ["com.vscodium"], folders: [
            Folder("Library/Application Support/VSCodium/Cache", .cache, source: "https://github.com/VSCodium/vscodium/blob/master/docs/migration.md#L23"),
            Folder("Library/Application Support/VSCodium/CachedData", .cache, source: "https://github.com/VSCodium/vscodium/blob/master/docs/migration.md#L23"),
            Folder("Library/Application Support/VSCodium/CachedExtensionVSIXs", .downloads, source: "https://github.com/VSCodium/vscodium/blob/master/docs/migration.md#L23"),
            Folder("Library/Caches/com.vscodium", .cache, source: "https://developer.apple.com/documentation/foundation/filemanager/searchpathdirectory/cachesdirectory"),
            Folder("Library/Application Support/VSCodium/logs", .logs, source: "https://github.com/microsoft/vscode/blob/main/src/vs/platform/environment/common/environmentService.ts#L73-L79"),
            Folder("Library/Application Support/VSCodium/Code Cache", .cache, source: "https://github.com/chromium/chromium/blob/main/content/browser/storage_partition_impl.cc#L1585"),
            Folder("Library/Application Support/VSCodium/GPUCache", .cache, source: "https://github.com/chromium/chromium/blob/main/gpu/ipc/common/gpu_disk_cache_type.cc#L46"),
            Folder("Library/Application Support/VSCodium/DawnWebGPUCache", .cache, source: "https://github.com/chromium/chromium/blob/main/gpu/ipc/common/gpu_disk_cache_type.cc#L48"),
            Folder("Library/Application Support/VSCodium/DawnGraphiteCache", .cache, source: "https://github.com/chromium/chromium/blob/main/gpu/ipc/common/gpu_disk_cache_type.cc#L50"),
            Folder("Library/Caches/com.vscodium.ShipIt", .downloads, source: "https://github.com/Squirrel/Squirrel.Mac/blob/main/Squirrel/SQRLShipItLauncher.m#L25-L26"),
        ]),
        Definition(id: "cursor", name: "Cursor", systemImage: "curlybraces", appBundleIdentifiers: ["com.todesktop.230313mzl4w4u92"], folders: [
            Folder("Library/Application Support/Cursor/Cache", .cache, source: "https://github.com/microsoft/vscode/blob/main/src/vs/platform/environment/node/userDataPath.ts#L95-L105"),
            Folder("Library/Application Support/Cursor/CachedData", .cache, source: "https://github.com/microsoft/vscode/blob/main/src/main.ts#L666"),
            Folder("Library/Application Support/Cursor/logs", .logs, source: "https://github.com/microsoft/vscode/blob/main/src/vs/platform/environment/common/environmentService.ts#L73-L79"),
            Folder("Library/Application Support/Cursor/Code Cache", .cache, source: "https://github.com/chromium/chromium/blob/main/content/browser/storage_partition_impl.cc#L1585"),
            Folder("Library/Application Support/Cursor/GPUCache", .cache, source: "https://github.com/chromium/chromium/blob/main/gpu/ipc/common/gpu_disk_cache_type.cc#L46"),
            Folder("Library/Application Support/Cursor/DawnWebGPUCache", .cache, source: "https://github.com/chromium/chromium/blob/main/gpu/ipc/common/gpu_disk_cache_type.cc#L48"),
            Folder("Library/Application Support/Cursor/DawnGraphiteCache", .cache, source: "https://github.com/chromium/chromium/blob/main/gpu/ipc/common/gpu_disk_cache_type.cc#L50"),
            Folder("Library/Application Support/Cursor/CachedExtensionVSIXs", .downloads, source: "https://github.com/microsoft/vscode/blob/main/src/vs/platform/environment/common/environmentService.ts#L127"),
        ]),
        Definition(id: "windsurf", name: "Windsurf & Devin", systemImage: "curlybraces", appBundleIdentifiers: ["com.exafunction.windsurf", "ai.cognition.devin"], folders: [
            Folder("Library/Application Support/Devin/Cache", .cache, source: "https://docs.devin.ai/desktop/cascade/workflows"),
            Folder("Library/Application Support/Devin/CachedData", .cache, source: "https://docs.devin.ai/desktop/cascade/workflows"),
            Folder("Library/Application Support/Windsurf/Cache", .cache, source: "https://docs.devin.ai/desktop/cascade/workflows"),
            Folder("Library/Application Support/Windsurf/CachedData", .cache, source: "https://docs.devin.ai/desktop/cascade/workflows"),
        ]),
        Definition(id: "nova", name: "Nova", systemImage: "curlybraces", appBundleIdentifiers: ["com.panic.Nova"], folders: [
            Folder("Library/Caches/com.panic.Nova", .cache, source: "https://developer.apple.com/documentation/foundation/filemanager/searchpathdirectory/cachesdirectory"),
        ]),
        Definition(id: "zed", name: "Zed", systemImage: "curlybraces", appBundleIdentifiers: ["dev.zed.Zed"], folders: [
            Folder("Library/Caches/Zed", .cache, source: "https://github.com/zed-industries/zed/blob/main/crates/paths/src/paths.rs#L192-L199"),
            Folder("Library/Logs/Zed", .logs, source: "https://github.com/zed-industries/zed/blob/main/crates/paths/src/paths.rs#L228-L235"),
            Folder("Library/Application Support/Zed/hang_traces", .logs, source: "https://github.com/zed-industries/zed/blob/main/crates/paths/src/paths.rs#L221-L225"),
            Folder("Library/Application Support/Zed/remote_servers", .downloads, source: "https://github.com/zed-industries/zed/blob/main/crates/paths/src/paths.rs#L474-L478"),
            Folder("Library/Application Support/Zed/languages", .environments, source: "https://github.com/zed-industries/zed/blob/main/crates/paths/src/paths.rs#L438-L444"),
            Folder("Library/Application Support/Zed/debug_adapters", .environments, source: "https://github.com/zed-industries/zed/blob/main/crates/paths/src/paths.rs#L446-L452"),
        ]),
        Definition(id: "sublime", name: "Sublime Text", systemImage: "curlybraces", appBundleIdentifiers: ["com.sublimetext.4", "com.sublimetext.3"], folders: [
            Folder("Library/Caches/Sublime Text", .cache, source: "https://www.sublimetext.com/docs/revert.html"),
            Folder("Library/Caches/com.sublimetext.4", .cache, source: "https://developer.apple.com/documentation/foundation/filemanager/searchpathdirectory/cachesdirectory"),
            Folder("Library/Caches/com.sublimetext.3", .cache, source: "https://developer.apple.com/documentation/foundation/filemanager/searchpathdirectory/cachesdirectory"),
        ]),
        Definition(id: "androidstudio", name: "Android Studio", systemImage: "curlybraces", appBundleIdentifiers: ["com.google.android.studio"], folders: [
            Folder("Library/Caches/Google/AndroidStudio*/caches", .cache, source: "https://developer.android.com/studio/troubleshoot"),
            Folder("Library/Caches/Google/AndroidStudio*/index", .cache, source: "https://developer.android.com/studio/troubleshoot"),
            Folder("Library/Caches/Google/AndroidStudio*/tmp", .cache, source: "https://developer.android.com/studio/troubleshoot"),
            Folder("Library/Logs/Google/AndroidStudio*", .logs, source: "https://developer.android.com/studio/troubleshoot"),
        ], ownFolders: ["Library/Caches/Google/AndroidStudio*", "Library/Logs/Google/AndroidStudio*"]),
        Definition(id: "neovim", name: "Neovim", systemImage: "curlybraces", appBundleIdentifiers: [], folders: [
            Folder(".cache/nvim", .cache, source: "https://github.com/neovim/neovim/blob/master/runtime/doc/starting.txt#L1404-L1405"),
            Folder(".local/share/nvim/lazy", .environments, source: "https://github.com/folke/lazy.nvim/blob/main/lua/lazy/core/config.lua#L8"),
            Folder(".local/share/nvim/lazy-rocks", .environments, source: "https://github.com/folke/lazy.nvim/blob/main/lua/lazy/core/config.lua#L61"),
            Folder(".local/share/nvim/mason", .environments, source: "https://github.com/mason-org/mason.nvim/blob/main/lua/mason/settings.lua#L9"),
            Folder(".local/state/nvim/lazy", .cache, source: "https://github.com/folke/lazy.nvim/blob/main/lua/lazy/core/config.lua#L220-L225"),
            Folder(".local/state/nvim/logs", .logs, source: "https://github.com/neovim/neovim/blob/master/runtime/doc/starting.txt#L1409-L1410"),
        ]),
        // Cloud tools
        Definition(id: "gcloud", name: "Google Cloud CLI", systemImage: "cloud", appBundleIdentifiers: [], folders: [
            Folder(".config/gcloud/logs", .logs, source: "https://docs.cloud.google.com/compute/docs/troubleshooting/general-tips"),
        ]),
        Definition(id: "azure", name: "Azure CLI", systemImage: "cloud", appBundleIdentifiers: [], folders: [
            Folder(".azure/logs", .logs, source: "https://github.com/microsoft/knack/blob/dev/knack/log.py#L182-L184"),
            Folder(".azure/telemetry", .cache, source: "https://github.com/Azure/azure-cli/blob/dev/src/azure-cli-telemetry/azure/cli/telemetry/util.py#L30"),
            Folder(".azure/commands", .logs, source: "https://github.com/Azure/azure-cli/blob/dev/src/azure-cli-core/azure/cli/core/azlogging.py#L61"),
        ]),
        Definition(id: "kubectl", name: "kubectl", systemImage: "cloud", appBundleIdentifiers: [], folders: [
            Folder(".kube/cache/discovery", .cache, source: "https://github.com/kubernetes/cli-runtime/blob/master/pkg/genericclioptions/config_flags.go#L317-L331"),
            Folder(".kube/cache/http", .cache, source: "https://github.com/kubernetes/cli-runtime/blob/master/pkg/genericclioptions/config_flags.go#L317"),
        ]),
        Definition(id: "helm", name: "Helm", systemImage: "cloud", appBundleIdentifiers: [], folders: [
            Folder("Library/Caches/helm", .cache, source: "https://github.com/helm/helm/blob/main/pkg/helmpath/lazypath_darwin.go#L32-L34"),
        ]),
        Definition(id: "githubcli", name: "GitHub CLI", systemImage: "cloud", appBundleIdentifiers: [], folders: [
            Folder(".cache/gh", .cache, source: "https://github.com/cli/go-gh/blob/trunk/pkg/config/config.go#L299-L306"),
        ]),
        Definition(id: "terraform", name: "Terraform", systemImage: "cloud", appBundleIdentifiers: [], folders: [
            Folder(".terraform.d/plugin-cache", .environments, source: "https://developer.hashicorp.com/terraform/cli/config/config-file"),
        ]),
        Definition(id: "pulumi", name: "Pulumi", systemImage: "cloud", appBundleIdentifiers: [], folders: [
            Folder(".pulumi/plugins", .downloads, source: "https://github.com/pulumi/docs/blob/master/content/docs/iac/concepts/plugins.md#L83"),
        ]),
        Definition(id: "vercel", name: "Vercel CLI", systemImage: "cloud", appBundleIdentifiers: [], folders: [
            Folder("Library/Caches/com.vercel.cli", .cache, source: "https://github.com/vercel/vercel/blob/main/packages/cli-config/src/paths.ts#L33-L35"),
        ]),
        // Netlify keeps its token in `config.json` in the same folder, so only these two subfolders are listed.
        Definition(id: "netlify", name: "Netlify CLI", systemImage: "cloud", appBundleIdentifiers: [], folders: [
            Folder("Library/Preferences/netlify/deno-cli", .downloads, source: "https://github.com/netlify/build/blob/main/packages/edge-bundler/node/bridge.ts#L66"),
            Folder("Library/Preferences/netlify/tunnel", .downloads, source: "https://github.com/netlify/cli/blob/main/src/utils/live-tunnel.ts#L86"),
        ]),
        Definition(id: "firebase", name: "Firebase CLI", systemImage: "cloud", appBundleIdentifiers: [], folders: [
            Folder(".cache/firebase", .downloads, source: "https://github.com/firebase/firebase-tools/blob/main/src/emulator/downloadableEmulators.ts#L29-L30"),
        ]),
        // Virtual machines
        Definition(id: "lima", name: "Lima", systemImage: "server.rack", appBundleIdentifiers: [], folders: [
            Folder("Library/Caches/lima", .downloads, source: "https://github.com/lima-vm/lima/blob/master/website/content/en/docs/dev/internals.md#L137-L145"),
        ]),
        Definition(id: "colima", name: "Colima", systemImage: "server.rack", appBundleIdentifiers: [], folders: [
            Folder("Library/Caches/colima", .downloads, source: "https://github.com/abiosoft/colima/blob/main/cmd/prune.go#L25-L41"),
        ]),
        Definition(id: "minikube", name: "minikube", systemImage: "server.rack", appBundleIdentifiers: [], folders: [
            Folder(".minikube/cache/iso", .downloads, source: "https://github.com/kubernetes/minikube/blob/master/site/content/en/docs/handbook/offline.md#L10-L17"),
            Folder(".minikube/cache/kic", .downloads, source: "https://github.com/kubernetes/minikube/blob/master/site/content/en/docs/handbook/offline.md#L10-L17"),
            Folder(".minikube/cache/preloaded-tarball", .downloads, source: "https://github.com/kubernetes/minikube/blob/master/site/content/en/docs/handbook/offline.md#L10-L17"),
        ]),
        Definition(id: "vagrant", name: "Vagrant", systemImage: "server.rack", appBundleIdentifiers: [], folders: [
            Folder(".vagrant.d/boxes", .keptDownloads, source: "https://github.com/hashicorp/vagrant/blob/main/lib/vagrant/environment.rb#L140"),
            Folder(".vagrant.d/tmp", .cache, source: "https://github.com/hashicorp/vagrant/blob/main/lib/vagrant/environment.rb#L143"),
        ]),
        // Build systems and media
        Definition(id: "ccache", name: "ccache", systemImage: "gearshape.2", appBundleIdentifiers: [], folders: [
            Folder("Library/Caches/ccache", .buildData, source: "https://github.com/ccache/ccache/blob/master/doc/manual.adoc#L575-L577"),
            // A legacy `~/.ccache` also holds `ccache.conf` (https://ccache.dev/manual/latest.html), so only
            // the cache's own shards and its temporary folder are named.
            Folder(".ccache/[0-9a-f]", .buildData, source: "https://github.com/ccache/ccache/blob/master/doc/manual.adoc#L375-L376"),
            Folder(".ccache/tmp", .buildData, source: "https://github.com/ccache/ccache/blob/master/doc/manual.adoc#L1246-L1252"),
        ]),
        Definition(id: "bazel", name: "Bazel", systemImage: "gearshape.2", appBundleIdentifiers: [], folders: [
            Folder("Library/Caches/bazel", .buildData, source: "https://github.com/bazelbuild/bazel/blob/master/docs/remote/output-directories.mdx#L32-L41"),
            Folder("Library/Caches/bazelisk", .downloads, source: "https://github.com/bazelbuild/bazelisk/blob/master/README.md#L312"),
        ]),
        Definition(id: "zig", name: "Zig", systemImage: "gearshape.2", appBundleIdentifiers: [], folders: [
            Folder(".cache/zig", .buildData, source: "https://codeberg.org/ziglang/zig/src/branch/master/lib/std/zig.zig#L1586-L1610"),
        ]),
        Definition(id: "vcpkg", name: "vcpkg", systemImage: "gearshape.2", appBundleIdentifiers: [], folders: [
            Folder(".cache/vcpkg/archives", .buildData, source: "https://github.com/microsoft/vcpkg-tool/blob/main/src/vcpkg/binarycaching.cpp#L1742-L1746"),
        ]),
        Definition(id: "conan", name: "Conan", systemImage: "gearshape.2", appBundleIdentifiers: [], folders: [
            Folder(".conan2/p", .environments, source: "https://github.com/conan-io/conan/blob/develop2/conan/internal/cache/cache.py#L27-L28"),
        ]),
        Definition(id: "pants", name: "Pants", systemImage: "gearshape.2", appBundleIdentifiers: [], folders: [
            Folder(".cache/pants/lmdb_store", .buildData, source: "https://github.com/pantsbuild/pants/blob/main/docs/docs/using-pants/troubleshooting-common-issues.mdx#L159"),
            Folder(".cache/pants/named_caches", .downloads, source: "https://github.com/pantsbuild/pants/blob/main/docs/docs/using-pants/troubleshooting-common-issues.mdx#L160"),
        ]),
        Definition(id: "unity", name: "Unity", systemImage: "cube.transparent", appBundleIdentifiers: ["com.unity3d.UnityEditor5.x"], folders: [
            // The Package Manager's cache of downloaded packages: `Library/Unity/cache` up to Unity 2022.3, and
            // `Library/Caches/Unity/upm` from Unity 6 (docs.unity3d.com, Manual/upm-cache.html for each version).
            Folder("Library/Caches/Unity/upm", .downloads, source: "https://docs.unity3d.com/Manual/upm-cache.html"),
            Folder("Library/Unity/cache", .downloads, source: "https://docs.unity3d.com/2022.3/Documentation/Manual/upm-cache.html"),
            Folder("Library/Unity/Asset Store-5.x", .keptDownloads, source: "https://docs.unity.com/asset-store/downloads/asset-store-packages"),
            Folder("Library/Logs/Unity", .logs, source: "https://docs.unity3d.com/Manual/log-files.html"),
        ]),
        Definition(id: "godot", name: "Godot", systemImage: "cube.transparent", appBundleIdentifiers: ["org.godotengine.godot"], folders: [
            Folder("Library/Caches/Godot", .cache, source: "https://github.com/godotengine/godot-docs/blob/master/tutorials/io/data_paths.rst#L157-L166"),
        ]),
        Definition(id: "blender", name: "Blender", systemImage: "cube.transparent", appBundleIdentifiers: ["org.blenderfoundation.blender"], folders: [
            Folder("Library/Caches/Blender", .cache, source: "https://projects.blender.org/blender/blender/src/branch/main/source/blender/blenkernel/intern/appdir.cc#L228"),
        ]),
        Definition(id: "adobe", name: "Adobe Media Cache", systemImage: "play.rectangle", appBundleIdentifiers: [], folders: [
            Folder("Library/Application Support/Adobe/Common/Media Cache Files", .cache, source: "https://helpx.adobe.com/premiere/desktop/troubleshooting/media-issues/manage-media-cache.html"),
            Folder("Library/Application Support/Adobe/Common/Media Cache", .cache, source: "https://helpx.adobe.com/premiere/desktop/troubleshooting/media-issues/manage-media-cache.html"),
        ]),
        // Quantum computing. Everything else these SDKs write in the home folder is settings or an account
        // token, so only these three folders are listed.
        Definition(id: "dwave", name: "D-Wave Ocean", systemImage: "atom", appBundleIdentifiers: [], folders: [
            Folder("Library/Caches/dwave-cloud-client", .cache, source: "https://github.com/dwavesystems/dwave-cloud-client/blob/master/dwave/cloud/config/loaders.py#L283-L289"),
        ]),
        Definition(id: "qutip", name: "QuTiP", systemImage: "atom", appBundleIdentifiers: [], folders: [
            Folder(".qutip/qutip_coeffs_*", .buildData, source: "https://github.com/qutip/qutip/blob/master/qutip/settings.py#L278-L283"),
        ]),
        Definition(id: "qbraid", name: "qBraid", systemImage: "atom", appBundleIdentifiers: [], folders: [
            Folder(".qbraid/environments", .environments, source: "https://docs.qbraid.com/cli/user-guide/environments"),
        ]),

        // Models and datasets
        Definition(id: "ollama", name: "Ollama", systemImage: "brain", appBundleIdentifiers: ["com.electron.ollama"], folders: [
            Folder(".ollama/models", .models, source: "https://github.com/ollama/ollama/blob/main/docs/faq.mdx#L233-L236"),
            Folder(".ollama/logs", .logs, source: "https://github.com/ollama/ollama/blob/main/docs/macos.mdx#L26-L28"),
            Folder("Library/Caches/ollama/updates", .downloads, source: "https://github.com/ollama/ollama/blob/main/app/updater/updater_darwin.go#L88-L96"),
        ]),
        Definition(id: "lmstudio", name: "LM Studio", systemImage: "brain", appBundleIdentifiers: [], folders: [
            Folder(".lmstudio/models", .models, source: "https://lmstudio.ai/docs/app/advanced/import-model"),
            Folder(".cache/lm-studio/models", .models, source: "https://lmstudio.ai/blog/lmstudio-v0.3.6"),
        ]),
        Definition(id: "huggingface", name: "Hugging Face", systemImage: "brain", appBundleIdentifiers: [], folders: [
            Folder(".cache/huggingface/hub", .models, source: "https://github.com/huggingface/huggingface_hub/blob/main/docs/source/en/package_reference/environment_variables.md#L37-L42"),
            Folder(".cache/huggingface/datasets", .models, source: "https://github.com/huggingface/datasets/blob/main/docs/source/cache.mdx#L20"),
            Folder(".cache/huggingface/xet", .cache, source: "https://github.com/huggingface/huggingface_hub/blob/main/docs/source/en/package_reference/environment_variables.md#L44-L48"),
            Folder(".cache/huggingface/assets", .cache, source: "https://github.com/huggingface/huggingface_hub/blob/main/docs/source/en/package_reference/environment_variables.md#L50-L56"),
            Folder(".cache/huggingface/transformers", .models, source: "https://github.com/huggingface/transformers/blob/v4.21.3/src/transformers/utils/hub.py#L70"),
            Folder(".cache/huggingface/modules", .cache, source: "https://github.com/huggingface/transformers/blob/main/src/transformers/utils/hub.py#L108"),
        ]),
        Definition(id: "torch", name: "PyTorch", systemImage: "brain", appBundleIdentifiers: [], folders: [
            Folder(".cache/torch/hub", .models, source: "https://github.com/pytorch/pytorch/blob/main/docs/source/hub.md#L122-L124"),
            Folder(".cache/torch/transformers", .models, source: "https://github.com/huggingface/transformers/blob/v4.21.3/src/transformers/utils/hub.py#L65"),
        ]),
        Definition(id: "mlxdata", name: "MLX Data", systemImage: "brain", appBundleIdentifiers: [], folders: [
            Folder(".cache/mlx.data", .models, source: "https://github.com/ml-explore/mlx-data/blob/main/python/mlx/data/datasets/common.py#L11"),
        ]),
        Definition(id: "whisper", name: "Whisper", systemImage: "brain", appBundleIdentifiers: [], folders: [
            Folder(".cache/whisper", .models, source: "https://github.com/openai/whisper/blob/main/whisper/__init__.py#L119-L134"),
        ]),
        Definition(id: "gpt4all", name: "GPT4All", systemImage: "brain", appBundleIdentifiers: [], folders: [
            Folder(".cache/gpt4all", .models, source: "https://github.com/nomic-ai/gpt4all/blob/main/gpt4all-bindings/python/gpt4all/gpt4all.py#L36"),
        ]),
        Definition(id: "tensorflow", name: "TensorFlow Datasets", systemImage: "brain", appBundleIdentifiers: [], folders: [
            Folder("tensorflow_datasets", .models, source: "https://github.com/tensorflow/datasets/blob/master/tensorflow_datasets/core/constants.py#L36-L37"),
        ]),
        Definition(id: "keras", name: "Keras", systemImage: "brain", appBundleIdentifiers: [], folders: [
            Folder(".keras/datasets", .models, source: "https://github.com/keras-team/keras/blob/master/keras/src/utils/file_utils.py#L230-L232"),
            Folder(".keras/models", .models, source: "https://github.com/keras-team/keras/blob/master/keras/src/applications/resnet.py#L209"),
        ]),
        Definition(id: "nltk", name: "NLTK Data", systemImage: "brain", appBundleIdentifiers: [], folders: [
            Folder("nltk_data", .models, source: "https://github.com/nltk/nltk/blob/develop/nltk/downloader.py#L1399-L1402"),
        ]),
        Definition(id: "llamacpp", name: "llama.cpp", systemImage: "brain", appBundleIdentifiers: [], folders: [
            Folder("Library/Caches/llama.cpp", .models, source: "https://github.com/ggml-org/llama.cpp/blob/master/common/common.cpp#L1051-L1068"),
        ]),
        Definition(id: "modelscope", name: "ModelScope", systemImage: "brain", appBundleIdentifiers: [], folders: [
            Folder(".cache/modelscope/hub", .models, source: "https://github.com/modelscope/modelscope/blob/master/modelscope/utils/file_utils.py#L41-L46"),
        ]),
        Definition(id: "kagglehub", name: "Kaggle Hub", systemImage: "brain", appBundleIdentifiers: [], folders: [
            Folder(".cache/kagglehub", .models, source: "https://github.com/Kaggle/kagglehub/blob/main/src/kagglehub/config.py#L17"),
        ]),
        Definition(id: "jan", name: "Jan", systemImage: "brain", appBundleIdentifiers: ["jan.ai.app"], folders: [
            Folder("Library/Application Support/Jan/data/llamacpp/models", .models, source: "https://jan.ai/docs/desktop/data-folder"),
            Folder("Library/Application Support/Jan/data/mlx/models", .models, source: "https://jan.ai/docs/desktop/data-folder"),
            Folder("Library/Application Support/Jan/data/logs", .logs, source: "https://jan.ai/docs/desktop/data-folder"),
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
                                source: folder.source,
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
