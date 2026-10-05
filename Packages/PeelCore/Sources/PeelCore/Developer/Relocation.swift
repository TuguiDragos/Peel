import Foundation

extension DeveloperCaches {
    /// A setting that moves a folder of the table elsewhere. The folder is looked for there as well as at its usual
    /// place, where an earlier setting may have left it.
    enum Relocation: Sendable {
        /// An Xcode preference that holds the folder's absolute path.
        case xcodeSetting(String)
        /// npm's cache, with the folder inside it.
        case npmCache(inside: String)
        /// Yarn 1's cache root, whose cache is a folder named for its cache version (`v6`).
        case yarnCache
        /// Yarn 2 and later's global folder, with the folder inside it.
        case yarnGlobalFolder(inside: String)
        /// pnpm's store folder, whose store is a folder named for its store version (`v10`, `v11`).
        case pnpmStore
        /// Go's module cache, with the folder inside it.
        case goModuleCache(inside: String)
        /// Go's build cache, which holds the `README` Go writes in it.
        case goBuildCache

        /// Where the tool says which file holds the setting and where the setting puts the folder.
        var sources: [String] {
            switch self {
            case .xcodeSetting: []
            case .npmCache: [
                "https://github.com/npm/cli/blob/b317f16c80df02ea3628cfa77170d5ae9b59720c/docs/lib/content/configuring-npm/npmrc.md#L17-L20",
                "https://github.com/npm/cli/blob/b317f16c80df02ea3628cfa77170d5ae9b59720c/workspaces/config/lib/definitions/definitions.js#L433-L444",
            ]
            case .yarnCache: [
                "https://github.com/yarnpkg/yarn/blob/c2dda503f3759b5be5f0e24ecd9cf5c97a540147/src/registries/yarn-registry.js#L34-L56",
                "https://github.com/yarnpkg/yarn/blob/c2dda503f3759b5be5f0e24ecd9cf5c97a540147/src/config.js#L352-L431",
            ]
            case .yarnGlobalFolder: [
                "https://github.com/yarnpkg/berry/blob/e4e423a1eb117b5129f20ac626a03eb7a97aedff/packages/yarnpkg-core/sources/Configuration.ts#L250-L254",
                "https://github.com/yarnpkg/berry/blob/e4e423a1eb117b5129f20ac626a03eb7a97aedff/packages/yarnpkg-core/sources/Configuration.ts#L1416-L1417",
            ]
            case .pnpmStore: [
                "https://github.com/pnpm/pnpm.io/blob/e36dcc555c137a77cd8c3fe5d62ba8d44636b33c/docs/cli/config.md#L19-L23",
                "https://github.com/pnpm/pnpm.io/blob/e36dcc555c137a77cd8c3fe5d62ba8d44636b33c/versioned_docs/version-10.x/cli/config.md#L14-L19",
                "https://github.com/pnpm/pnpm/blob/9287c31cea69206c4eeca7f21cd21df81d0b93e7/config/config/src/index.ts#L231-L236",
                "https://github.com/pnpm/pnpm/blob/fca2d32621419e34897a114a2f14199344bdb8fc/pnpm11/store/path/src/index.ts#L39-L42",
            ]
            case .goModuleCache: [
                "https://github.com/golang/go/blob/a90c4a7a586c70f0de61f5507d5c347702432e39/src/cmd/go/internal/cfg/cfg.go#L347-L363",
                "https://github.com/golang/go/blob/a90c4a7a586c70f0de61f5507d5c347702432e39/src/cmd/go/internal/cfg/cfg.go#L470",
            ]
            case .goBuildCache: [
                "https://github.com/golang/go/blob/a90c4a7a586c70f0de61f5507d5c347702432e39/src/cmd/go/internal/cfg/cfg.go#L347-L363",
                "https://github.com/golang/go/blob/a90c4a7a586c70f0de61f5507d5c347702432e39/src/cmd/go/internal/cache/default.go#L25-L31",
            ]
            }
        }

        /// The places the setting moves the folder to, each with the folder the setting names, which is the tool's
        /// own. Only real folders count: a link moves nothing.
        func places(preference: (String) -> String?, settings: ToolSettings) -> [(place: URL, named: URL)] {
            let found: [(place: URL, named: URL)] = switch self {
            case .xcodeSetting(let key):
                preference(key).map { NSString(string: $0).expandingTildeInPath }.flatMap { path in
                    path.hasPrefix("/") ? URL(filePath: path, directoryHint: .isDirectory) : nil
                }.map { [($0, $0)] } ?? []
            case .npmCache(let inside):
                settings.npmCache.map { [($0.appending(path: inside, directoryHint: .isDirectory), $0)] } ?? []
            case .yarnCache:
                settings.yarnCacheRoot.map { root in Self.versions(in: root).map { ($0, root) } } ?? []
            case .yarnGlobalFolder(let inside):
                settings.yarnGlobalFolder.map { [($0.appending(path: inside, directoryHint: .isDirectory), $0)] } ?? []
            case .pnpmStore:
                // A store folder that already ends with the store's version is the store itself.
                settings.pnpmStoreFolders.flatMap { folder in
                    Self.isAVersion(folder.lastPathComponent)
                        ? [(folder, folder)] : Self.versions(in: folder).map { ($0, folder) }
                }
            case .goModuleCache(let inside):
                settings.goModuleCache.map { [($0.appending(path: inside, directoryHint: .isDirectory), $0)] } ?? []
            case .goBuildCache:
                settings.goBuildCache.flatMap { Self.holdsGosReadme($0) ? [($0, $0)] : nil } ?? []
            }
            return found.map { (Self.entry($0.place), Self.entry($0.named)) }.filter(\.place.isRealFolder)
        }

        /// The entry a place names, without a final `/`: with one, the kernel follows a link to what it leads to.
        private static func entry(_ url: URL) -> URL {
            let path = url.path(percentEncoded: false)
            return URL(filePath: path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path)
        }

        /// The folders in `root` named for a version of the tool's layout, such as `v6`.
        private static func versions(in root: URL) -> [URL] {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path(percentEncoded: false))) ?? []
            return names.filter(isAVersion).sorted().map { root.appending(path: $0, directoryHint: .isDirectory) }
        }

        private static func isAVersion(_ name: String) -> Bool {
            name.count > 1 && name.first == "v" && name.dropFirst().allSatisfy { $0.isASCII && $0.isNumber }
        }

        /// The first line of the `README` Go writes in its build cache, which no other folder holds.
        private static let goReadme = "This directory holds cached build artifacts from the Go build system."

        private static func holdsGosReadme(_ folder: URL) -> Bool {
            let readme = folder.appending(path: "README")
            guard let start = BoundedRead.prefix(of: readme, count: goReadme.utf8.count) else { return false }
            return String(decoding: start, as: UTF8.self) == goReadme
        }
    }
}
