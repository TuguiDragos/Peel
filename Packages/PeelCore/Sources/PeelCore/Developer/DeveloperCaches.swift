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
        /// What an editor kept for a project that is no longer on this Mac, its chat history included. Nothing makes
        /// it again.
        case projectState
    }

    /// What an Xcode archive's own `Info.plist` says of the app inside it.
    public struct Archive: Sendable, Hashable {
        public let version: String?
        public let build: String?

        /// The version as Xcode's Organizer writes it, `2.1 (45)`, or whichever of the two the archive names.
        public var label: String? {
            switch (version, build) {
            case let (version?, build?): "\(version) (\(build))"
            case let (version, build): version ?? build
            }
        }
    }

    /// What the `info.plist` Xcode writes in a DerivedData folder says of the workspace the folder was built for.
    public struct Workspace: Sendable, Hashable {
        public let name: String
        public let lastUsed: Date?

        /// True when the workspace was opened within the last week, or when Xcode wrote no date for it.
        public var mayStillBeInUse: Bool {
            lastUsed.map { $0 > Date.now.addingTimeInterval(-ProjectArtifacts.recentlyActive) } ?? true
        }
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
        public var archive: Archive?
        public var workspace: Workspace?
        /// The name of the project an editor kept this for, which is no longer on this Mac.
        public var project: String?
        /// False for a folder among the tool's own that nothing shows the tool made. It is listed and never selected.
        public var isTheTools = true
        /// The newest write inside, from the walk that measured it. It is shown and never decides what is selected.
        public var lastWritten: Date?
        /// A wallet, a signing key, or a password database seen inside. Never a repository: the tool clones it again.
        public var heldBack: HoldBack?

        public var id: URL { url }

        /// Whether Peel recommends this location, which Select Recommended selects and `peel caches --remove` moves:
        /// only content that tools make or fetch again, or logs, and only once measured.
        public var isRecommended: Bool {
            guard isTheTools, workspace?.mayStillBeInUse != true, heldBack == nil else { return false }
            return switch kind {
            case .buildData, .downloads, .cache, .logs: size != nil
            case .deviceSupport, .archives, .models, .environments, .keptDownloads, .projectState: false
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

    public var selectableRows: SelectableRows<URL> {
        SelectableRows(
            rows: locations.map(\.url),
            selectable: locations.map(\.url),
            recommended: locations.filter(\.isRecommended).map(\.url)
        )
    }

    /// The name of one of the environment's apps that is running, which is the one to ask the user to quit, or nil
    /// when none runs. Nothing of the environment moves while one runs, from the app or `peel`: it writes in these
    /// folders. Asked each time, since an app can be opened at any moment.
    public var runningApp: String? {
        appBundleIdentifiers.lazy.compactMap { identifier in
            NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
                .lazy.compactMap(\.localizedName).first
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

    /// A folder a tool keeps, relative to the home folder or to the user's cache folder, and what it holds.
    struct Folder {
        enum Base {
            case home
            /// The folder macOS gives each user for caches, `getconf DARWIN_USER_CACHE_DIR`.
            case userCache
            /// The folder macOS gives each user for temporary files, `getconf DARWIN_USER_TEMP_DIR`. What a program
            /// still has open there is never listed: it is in use, not left behind.
            case userTemporary
        }

        let path: String
        let kind: DeveloperEnvironment.ContentKind
        /// Where the tool documents the folder: a page, or the file inside Xcode that names it.
        let source: String
        /// A store the tool can turn on inside the folder, which projects then link into. While an entry by that
        /// name is there, a link included, the folder is listed without a checkmark: moving it breaks them.
        let storeInside: String?
        /// How far inside the folder its rows are: 0 lists it whole, 1 lists each folder in it, as Xcode keeps one per
        /// system version, and 2 each folder two levels down, as Xcode keeps each archive in a folder for its day.
        let rowsDepth: Int
        /// The ending every row's name has, such as `.xcarchive`, or nil for any.
        let rowEnding: String?
        /// True for Xcode's DerivedData, whose rows are the tool's own only when `derivedDataRow(at:)` shows it.
        let rowsAreDerivedData: Bool
        /// True for an editor's `workspaceStorage`, whose rows are listed only when `goneProject(at:)` names one.
        let rowsAreProjectState: Bool
        /// The setting that moves the folder elsewhere: Xcode's, or one in the tool's own configuration file.
        let movedBy: Relocation?
        let base: Base
        /// The links, relative to the home folder, a tool's installer puts on the path to the version it runs. When
        /// set, the folder's rows are the versions it keeps beside that one (`olderVersions(in:home:)`).
        let launchers: [String]
        /// Where a Git clone here comes from when it is the tool's own, as `ToolSettings.gitAddress` writes it. A clone
        /// of anything else, which the person may have added under the same name, is listed and never selected.
        let clonedFrom: String?

        init(
            _ path: String, _ kind: DeveloperEnvironment.ContentKind, source: String, storeInside: String? = nil,
            rowsDepth: Int = 0, rowEnding: String? = nil, rowsAreDerivedData: Bool = false,
            rowsAreProjectState: Bool = false, movedBy: Relocation? = nil, base: Base = .home,
            launchers: [String] = [], clonedFrom: String? = nil
        ) {
            self.path = path
            self.kind = kind
            self.source = source
            self.storeInside = storeInside
            self.rowsDepth = rowsDepth
            self.rowEnding = rowEnding
            self.rowsAreDerivedData = rowsAreDerivedData
            self.rowsAreProjectState = rowsAreProjectState
            self.movedBy = movedBy
            self.base = base
            self.launchers = launchers
            self.clonedFrom = clonedFrom
        }

        /// Whether what is at `url` is the tool's own, as far as where it was cloned from says.
        func isTheTools(at url: URL) -> Bool {
            clonedFrom.map { ToolSettings.cloneAddress(of: url) == $0 } ?? true
        }

        /// The versions in `folder` beside the ones its launchers run, or none when a launcher is not the installer's
        /// link into it: a launcher of the person's own may run any version, so none can be called old.
        func olderVersions(in folder: URL, home: URL) -> [URL] {
            let base = PathComponents.of(PathPattern.comparablePath(of: folder))
            var running: Set<String> = []
            for launcher in launchers {
                let link = home.appending(path: launcher)
                let path = link.path(percentEncoded: false)
                guard let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: path) else {
                    if link.isMissing { continue }
                    return []
                }
                let target = URL(filePath: destination, relativeTo: link.deletingLastPathComponent())
                    .standardizedFileURL
                let names = PathComponents.of(PathPattern.comparablePath(of: target))
                guard names.count > base.count, names.starts(with: base) else { return [] }
                running.insert(names[base.count])
            }
            guard !running.isEmpty else { return [] }
            let entries = (try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: [.isSymbolicLinkKey], options: [.skipsHiddenFiles]
            )) ?? []
            return entries.filter { entry in
                (try? entry.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true
            }.map { folder.appending(path: $0.lastPathComponent) }
                .filter { !running.contains(PathComponents.of(PathPattern.comparablePath(of: $0)).last ?? "") }
        }

        /// Where the folder is: at `path` in its base, and where the setting that moves it says.
        func places(
            home: URL, userCache: URL?, userTemporary: URL?, preference: (String) -> String?, settings: ToolSettings
        ) -> [URL] {
            let root = switch base {
            case .home: home
            case .userCache: userCache
            case .userTemporary: userTemporary
            }
            guard let root else { return [] }
            var places = PathPattern.expand(path, home: root, from: .peel)
            places += movedBy?.places(preference: preference, settings: settings).map(\.place) ?? []
            var seen: Set<String> = []
            return places.filter { seen.insert(PathPattern.comparablePath(of: $0)).inserted }
        }

        func rows(in folder: URL) -> [URL] {
            var level = [folder]
            for _ in 0..<rowsDepth {
                level = level.flatMap { folder in
                    let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
                    let entries = (try? FileManager.default.contentsOfDirectory(
                        at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]
                    )) ?? []
                    // Named from `folder`, which keeps the spelling the rest of the list uses.
                    return entries.filter { entry in
                        let values = try? entry.resourceValues(forKeys: Set(keys))
                        return values?.isDirectory == true && values?.isSymbolicLink != true
                    }.map { folder.appending(path: $0.lastPathComponent, directoryHint: .notDirectory) }
                }
            }
            guard rowsDepth > 0, let rowEnding else { return level }
            return level.filter { $0.lastPathComponent.hasSuffix(rowEnding) }
        }

        /// What the folder at `url` holds now: installed packages once its store is there, `kind` otherwise.
        func kind(at url: URL) -> DeveloperEnvironment.ContentKind {
            guard let storeInside else { return kind }
            let store = url.appending(path: storeInside).path(percentEncoded: false)
            return (try? FileManager.default.attributesOfItem(atPath: store)) != nil ? .environments : kind
        }
    }

    /// A setting of Xcode's that holds a path, as Xcode's Settings > Locations writes it.
    @Sendable static func xcodePreference(_ key: String) -> String? {
        CFPreferencesCopyAppValue(key as CFString, "com.apple.dt.Xcode" as CFString) as? String
    }

    /// The caches Xcode 27 names inside DerivedData, beside the folder it makes for each workspace.
    private static let derivedDataCaches: Set<String> = [
        "ModuleCache.noindex", "SDKStatCaches.noindex", "CompilationCache.noindex", "SymbolCache.noindex",
        "SDKExplicitPrecompiledModules",
    ]

    /// Whether a folder in DerivedData is Xcode's, and the workspace it was built for: a cache Xcode names, or a
    /// folder whose `info.plist` names its workspace, as Xcode writes one in each.
    static func derivedDataRow(at url: URL) -> (workspace: DeveloperEnvironment.Workspace?, isXcodes: Bool) {
        guard !derivedDataCaches.contains(url.lastPathComponent) else { return (nil, true) }
        guard
            let info = BoundedRead.propertyList(at: url.appending(path: "info.plist"), maximum: 64 * 1_024),
            let path = info["WorkspacePath"] as? String, !path.isEmpty
        else { return (nil, false) }
        let name = URL(filePath: path).deletingPathExtension().lastPathComponent
        return (DeveloperEnvironment.Workspace(name: name, lastUsed: info["LastAccessedDate"] as? Date), true)
    }

    /// The name of the project whose state VS Code, or an editor built on it, keeps at `url`, when that project is
    /// gone: the `workspace.json` it writes names its folder or workspace file, which is missing from a folder that
    /// is still there. A project on a disk that is not connected, or on another machine, is not known to be gone.
    static func goneProject(at url: URL) -> String? {
        guard
            let data = BoundedRead.data(at: url.appending(path: "workspace.json"), maximum: 64 * 1_024),
            let meta = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let written = meta["folder"] as? String ?? meta["workspace"] as? String,
            let project = URL(string: written), project.isFileURL,
            project.isMissing, !project.deletingLastPathComponent().isMissing
        else { return nil }
        return meta["folder"] != nil ? project.lastPathComponent : project.deletingPathExtension().lastPathComponent
    }

    static func archive(at url: URL) -> DeveloperEnvironment.Archive? {
        guard
            let facts = BoundedRead.propertyList(at: url.appending(path: "Info.plist")),
            let app = facts["ApplicationProperties"] as? [String: Any]
        else { return nil }
        let version = app["CFBundleShortVersionString"] as? String
        let build = app["CFBundleVersion"] as? String
        guard version != nil || build != nil else { return nil }
        return DeveloperEnvironment.Archive(version: version, build: build)
    }

    /// The table's folders under one home, which Space leaves to the Developer page, worked out once for all the
    /// folders of an area.
    struct FoldersLeftToDeveloper {
        private let folders: [(path: [String], own: [[String]])]

        init(home: URL, userCache: URL? = nil) {
            // Not through `comparablePath`: standardizing drops `/private` only from a path that exists, and most
            // paths in the table don't.
            let names = { (url: URL) in PathComponents.of(PathPattern.canonical(url).path(percentEncoded: false)) }
            let homeNames = names(home)
            let userCacheNames = userCache.map(names)
            // A tool's configuration can move a cache into a place Space shows, and the folder it names is the
            // tool's own there.
            let settings = ToolSettings(home: home)
            folders = DeveloperCaches.definitions.flatMap { definition in
                let own = definition.ownFolders.map { homeNames + PathComponents.of($0) }
                let usual = definition.folders.compactMap { folder -> ([String], [[String]])? in
                    let base = switch folder.base {
                    case .home: homeNames
                    case .userCache: userCacheNames
                    case .userTemporary: nil as [String]?
                    }
                    return base.map { ($0 + PathComponents.of(folder.path), own) }
                }
                let moved = definition.folders.compactMap(\.movedBy).flatMap { relocation in
                    relocation.places(preference: { _ in nil }, settings: settings).map {
                        (names($0.place), [names($0.named)])
                    }
                }
                return usual + moved
            }
        }

        /// The tools' own folders inside `folder`, as the name patterns leading to each (`["Google",
        /// "AndroidStudio*"]`). The folder is read as the kernel names it, as the home is, so another spelling of the
        /// same folder (another case, a link) finds the same.
        func inside(_ folder: URL) -> [[String]] {
            let base = PathComponents.of(PathPattern.canonical(folder).path(percentEncoded: false))
            let owned = folders.compactMap { path, own -> [String]? in
                guard path.count > base.count, path.starts(with: base) else { return nil }
                let declared = own.first { $0.count > base.count && path.starts(with: $0) }
                return Array((declared ?? Array(path.prefix(base.count + 1)))[base.count...])
            }
            return Set(owned).sorted { $0.joined(separator: "/") < $1.joined(separator: "/") }
        }
    }

    /// The folders the Developer page offers, relative to the home folder. Only folders one tool owns outright
    /// belong here: no toolchain or installation, nothing holding an account or a token, no path inside another.
    static let definitions: [Definition] = [
        // Apple
        Definition(id: "xcode", name: "Xcode", systemImage: "hammer", appBundleIdentifiers: ["com.apple.dt.Xcode", "com.apple.iphonesimulator"], folders: [
            Folder(
                "Library/Developer/Xcode/DerivedData", .buildData,
                source: "https://developer.apple.com/documentation/xcode-release-notes/xcode-26-release-notes",
                rowsDepth: 1, rowsAreDerivedData: true, movedBy: .xcodeSetting("IDECustomDerivedDataLocation")
            ),
            Folder("Library/Developer/Xcode/UserData/Previews/Simulator Devices", .buildData, source: "Xcode 27: DVTSystemPrerequisites.framework, beside DVTSimulatorDeviceRemover"),
            Folder("Library/Developer/Xcode/UserData-Tests/Previews/Simulator Devices", .buildData, source: "Xcode 27: DVTSystemPrerequisites.framework, beside DVTSimulatorDeviceRemover"),
            Folder("Library/Developer/Xcode/UserData/IB Support/Simulator Devices", .buildData, source: "Xcode 27: DVTSystemPrerequisites.framework, beside DVTSimulatorDeviceRemover"),
            Folder("Library/Developer/Xcode/UserData/RT Support/Simulator Devices", .buildData, source: "Xcode 27: DVTSystemPrerequisites.framework, beside DVTSimulatorDeviceRemover"),
            Folder("Library/Developer/XCTestDevices", .buildData, source: "Xcode 27: DVTSystemPrerequisites.framework, beside DVTSimulatorDeviceRemover"),
            Folder("Library/Developer/XCPGDevices", .buildData, source: "Xcode 27: DVTSystemPrerequisites.framework, beside DVTSimulatorDeviceRemover"),
            Folder("Library/Developer/Xcode/iOS DeviceSupport", .deviceSupport, source: "https://developer.apple.com/documentation/xcode-release-notes/xcode-12_2-release-notes", rowsDepth: 1),
            Folder("Library/Developer/Xcode/watchOS DeviceSupport", .deviceSupport, source: "Xcode 27: CoreSymbolicationDT.framework/Resources/JSONCrashLog/DeviceSupportDirectories.py", rowsDepth: 1),
            Folder("Library/Developer/Xcode/tvOS DeviceSupport", .deviceSupport, source: "Xcode 27: CoreSymbolicationDT.framework/Resources/JSONCrashLog/DeviceSupportDirectories.py", rowsDepth: 1),
            Folder("Library/Developer/Xcode/visionOS DeviceSupport", .deviceSupport, source: "Xcode 27: DVTFoundation.framework (\"%@ DeviceSupport\") and XROS.platform/Info.plist (Description visionOS)", rowsDepth: 1),
            Folder("Library/Developer/Xcode/macOS DeviceSupport", .deviceSupport, source: "Xcode 27: CoreSymbolicationDT.framework/Resources/JSONCrashLog/DeviceSupportDirectories.py", rowsDepth: 1),
            Folder("Library/Developer/Xcode/DocumentationCache", .cache, source: "Xcode 27: DVTFoundation.framework, -[DVTDeveloperPaths documentationCacheDirectoryForCurrentApplication]"),
            Folder("Library/Developer/CoreSimulator/Caches", .cache, source: "https://developer.apple.com/documentation/xcode-release-notes/xcode-12_3-release-notes"),
            Folder("Library/Logs/CoreSimulator", .logs, source: "Xcode 27: /Library/Developer/PrivateFrameworks/CoreSimulator.framework (\"%s/Library/Logs/CoreSimulator\")"),
            Folder("Library/Caches/com.apple.dt.Xcode", .cache, source: "https://developer.apple.com/documentation/foundation/filemanager/searchpathdirectory/cachesdirectory"),
            Folder("Library/Developer/Packages", .keptDownloads, source: "https://developer.apple.com/documentation/xcode-release-notes/xcode-16_2-release-notes"),
            Folder(
                "Library/Developer/Xcode/Archives", .archives,
                source: "Xcode 27: IDEFoundation.framework, -[IDEDeveloperPaths defaultDistributionArchivesLocation]",
                rowsDepth: 2, rowEnding: ".xcarchive", movedBy: .xcodeSetting("IDECustomDistributionArchivesLocation")
            ),
        ]),
        Definition(id: "swiftpm", name: "Swift Package Manager", systemImage: "swift", appBundleIdentifiers: [], folders: [
            Folder("Library/Caches/org.swift.swiftpm", .downloads, source: "https://github.com/swiftlang/swift-package-manager/blob/708c2736d671a3c32a6a058cd3ee331b36852876/Sources/Basics/FileSystem/FileSystem+Extensions.swift#L246-L253"),
        ]),
        Definition(id: "cocoapods", name: "CocoaPods", systemImage: "shippingbox", appBundleIdentifiers: [], folders: [
            Folder("Library/Caches/CocoaPods", .downloads, source: "https://github.com/CocoaPods/CocoaPods/blob/b80e113e28a7e23cd6dbc169f0c923f6b48bf7a2/lib/cocoapods/config.rb#L23"),
            // The CDN copy of the public spec index. The spec repositories a person added sit beside it and stay.
            Folder(".cocoapods/repos/trunk", .cache, source: "https://github.com/CocoaPods/Core/blob/4c1beb2e068e1055d8ed9fa079f94e7817157ba3/lib/cocoapods-core/trunk_source.rb#L2-L7"),
            // The Git clone of the same index, which CocoaPods made as `master` before it read the CDN, and which its
            // 1.8 notes say may go once projects read the CDN; added now, it is named `cocoapods`
            // (`Source::Manager#name_for_url`).
            Folder(".cocoapods/repos/master", .downloads, source: "https://blog.cocoapods.org/CocoaPods-1.8.0-beta/", clonedFrom: "github.com/cocoapods/specs"),
            Folder(".cocoapods/repos/cocoapods", .downloads, source: "https://github.com/CocoaPods/Core/blob/4c1beb2e068e1055d8ed9fa079f94e7817157ba3/lib/cocoapods-core/source/manager.rb#L426-L478", clonedFrom: "github.com/cocoapods/specs"),
        ]),
        Definition(id: "carthage", name: "Carthage", systemImage: "shippingbox", appBundleIdentifiers: [], folders: [
            Folder("Library/Caches/org.carthage.CarthageKit", .downloads, source: "https://github.com/Carthage/Carthage/blob/e33e133a5427129b38bfb1ae18d8f56b29a93204/Source/CarthageKit/Constants.swift#L31"),
        ]),
        Definition(id: "homebrew", name: "Homebrew", systemImage: "mug", appBundleIdentifiers: [], folders: [
            Folder("Library/Caches/Homebrew/downloads", .downloads, source: "https://github.com/Homebrew/brew/blob/1299da92f98e1284cc762977c0e2de31dbb5854c/Library/Homebrew/download_strategy/abstract_file_download_strategy.rb#L42"),
            Folder("Library/Caches/Homebrew/Cask", .downloads, source: "https://github.com/Homebrew/brew/blob/1299da92f98e1284cc762977c0e2de31dbb5854c/Library/Homebrew/cask/cache.rb#L9"),
            Folder("Library/Caches/Homebrew/bootsnap", .cache, source: "https://github.com/Homebrew/brew/blob/1299da92f98e1284cc762977c0e2de31dbb5854c/Library/Homebrew/startup/bootsnap.rb#L45"),
            Folder("Library/Caches/Homebrew/*_cache", .cache, source: "https://github.com/Homebrew/brew/blob/1299da92f98e1284cc762977c0e2de31dbb5854c/Library/Homebrew/package_manager_cache.rb#L8-L27"),
            Folder("Library/Caches/Homebrew/glide_home", .cache, source: "https://github.com/Homebrew/brew/blob/1299da92f98e1284cc762977c0e2de31dbb5854c/Library/Homebrew/package_manager_cache.rb#L15"),
            Folder("Library/Caches/Homebrew/api-source", .downloads, source: "https://github.com/Homebrew/brew/blob/1299da92f98e1284cc762977c0e2de31dbb5854c/Library/Homebrew/api.rb#L26"),
            Folder("Library/Caches/Homebrew/gh-actions-artifact", .downloads, source: "https://github.com/Homebrew/brew/blob/1299da92f98e1284cc762977c0e2de31dbb5854c/Library/Homebrew/utils/github/artifacts/github_artifact_download_strategy.rb#L9"),
            Folder("Library/Logs/Homebrew", .logs, source: "https://github.com/Homebrew/brew/blob/1299da92f98e1284cc762977c0e2de31dbb5854c/Library/Homebrew/utils/os.sh#L55-L56"),
        ]),
        Definition(id: "swiftlint", name: "SwiftLint", systemImage: "swift", appBundleIdentifiers: [], folders: [
            Folder("Library/Caches/SwiftLint", .cache, source: "https://github.com/realm/SwiftLint/blob/ec4691d9e813a1d3358e82917326b56b0a71d3c9/Source/SwiftLintFramework/Configuration/Configuration+Cache.swift#L80-L85"),
        ]),
        Definition(id: "tuist", name: "Tuist", systemImage: "hammer", appBundleIdentifiers: [], folders: [
            Folder(".cache/tuist", .buildData, source: "https://github.com/tuist/tuist/blob/9365e96671e69386cccae77079743ff871e14b79/server/priv/docs/en/cli/directories.md"),
        ]),
        // JavaScript
        Definition(id: "npm", name: "npm", systemImage: "cube", appBundleIdentifiers: [], folders: [
            Folder(".npm/_cacache", .downloads, source: "https://github.com/npm/cli/blob/b317f16c80df02ea3628cfa77170d5ae9b59720c/workspaces/config/lib/definitions/definitions.js#L443", movedBy: .npmCache(inside: "_cacache")),
            Folder(".npm/_npx", .downloads, source: "https://github.com/npm/cli/blob/b317f16c80df02ea3628cfa77170d5ae9b59720c/workspaces/config/lib/definitions/definitions.js#L444", movedBy: .npmCache(inside: "_npx")),
            Folder(".npm/_logs", .logs, source: "https://github.com/npm/cli/blob/b317f16c80df02ea3628cfa77170d5ae9b59720c/workspaces/config/lib/definitions/definitions.js#L1481-L1486", movedBy: .npmCache(inside: "_logs")),
            Folder(".npm/_prebuilds", .downloads, source: "https://github.com/prebuild/prebuild-install/blob/8e4dbad54ac92c480e2ff213d46140b5fd9a3545/README.md#L148-L154", movedBy: .npmCache(inside: "_prebuilds")),
        ]),
        Definition(id: "yarn", name: "Yarn", systemImage: "cube", appBundleIdentifiers: [], folders: [
            Folder("Library/Caches/Yarn", .downloads, source: "https://github.com/yarnpkg/yarn/blob/c2dda503f3759b5be5f0e24ecd9cf5c97a540147/src/util/user-dirs.js#L32-L33", movedBy: .yarnCache),
            // Yarn's Plug'n'Play projects load every package from this cache, so it is listed and never selected:
            // moving it breaks each such project until `yarn install` runs in it again.
            Folder(".yarn/berry/cache", .environments, source: "https://github.com/yarnpkg/berry/blob/e4e423a1eb117b5129f20ac626a03eb7a97aedff/packages/yarnpkg-core/sources/Configuration.ts", movedBy: .yarnGlobalFolder(inside: "cache")),
            Folder(".yarn/berry/metadata", .cache, source: "https://github.com/yarnpkg/berry/blob/e4e423a1eb117b5129f20ac626a03eb7a97aedff/packages/plugin-npm/sources/npmHttpUtils.ts#L317", movedBy: .yarnGlobalFolder(inside: "metadata")),
        ]),
        Definition(id: "pnpm", name: "pnpm", systemImage: "cube", appBundleIdentifiers: [], folders: [
            Folder("Library/pnpm/store", .environments, source: "https://github.com/pnpm/pnpm.io/blob/ae60a09ef4fe5929d937a24df02e21ecd08c3edc/docs/settings/store.md#L15", movedBy: .pnpmStore),
            Folder(".pnpm-store", .environments, source: "https://github.com/pnpm/pnpm.io/blob/ae60a09ef4fe5929d937a24df02e21ecd08c3edc/versioned_docs_archived/version-6.x/npmrc.md#L95-L100"),
            Folder("Library/Caches/pnpm", .cache, source: "https://github.com/pnpm/pnpm.io/blob/ae60a09ef4fe5929d937a24df02e21ecd08c3edc/docs/settings/other.md#L175"),
        ]),
        Definition(id: "bun", name: "Bun", systemImage: "cube", appBundleIdentifiers: [], folders: [
            // Bun's global virtual store, once turned on, is `links`, and every project's `node_modules` then points
            // into it (Bun's documentation, "Global virtual store").
            Folder(".bun/install/cache", .downloads, source: "https://github.com/oven-sh/bun/blob/aa8307619d8dccbda113a5a4aa1885e0cef7eaba/docs/pm/global-store.mdx", storeInside: "links"),
            Folder("Library/Caches/bun", .cache, source: "https://github.com/oven-sh/bun/blob/aa8307619d8dccbda113a5a4aa1885e0cef7eaba/src/jsc/RuntimeTranspilerCache.rs#L657-L660"),
        ]),
        Definition(id: "deno", name: "Deno", systemImage: "chevron.left.forwardslash.chevron.right", appBundleIdentifiers: [], folders: [
            // `DENO_DIR` keeps the REPL history (`deno_history.txt`) and what scripts store (`location_data`)
            // beside its caches, so the caches are named one by one, as Deno's `deno_dir.rs` names them. `deps` and
            // the `_v1` databases are Deno 1's names.
            Folder("Library/Caches/deno/remote", .downloads, source: "https://github.com/denoland/deno/blob/b4f08f127652d8442b4d3dbabc277aca3840bc1d/libs/resolver/cache/deno_dir.rs"),
            Folder("Library/Caches/deno/deps", .downloads, source: "https://github.com/denoland/deno/blob/a98e146a55b209458160bcd148497310a9e14441/cli/cache/deno_dir.rs"),
            Folder("Library/Caches/deno/npm", .downloads, source: "https://github.com/denoland/deno/blob/b4f08f127652d8442b4d3dbabc277aca3840bc1d/libs/resolver/cache/deno_dir.rs"),
            Folder("Library/Caches/deno/dl", .downloads, source: "https://github.com/denoland/deno/blob/b4f08f127652d8442b4d3dbabc277aca3840bc1d/libs/resolver/cache/deno_dir.rs"),
            Folder("Library/Caches/deno/gen", .buildData, source: "https://github.com/denoland/deno/blob/b4f08f127652d8442b4d3dbabc277aca3840bc1d/libs/resolver/cache/deno_dir.rs"),
            Folder("Library/Caches/deno/registries", .cache, source: "https://github.com/denoland/deno/blob/b4f08f127652d8442b4d3dbabc277aca3840bc1d/libs/resolver/cache/deno_dir.rs"),
            Folder("Library/Caches/deno/*_cache_v1", .cache, source: "https://github.com/denoland/deno/blob/9e575a286269c38c1af0a918a2a4ea4639a3004b/cli/cache/deno_dir.rs"),
            Folder("Library/Caches/deno/*_cache_v2", .cache, source: "https://github.com/denoland/deno/blob/b4f08f127652d8442b4d3dbabc277aca3840bc1d/libs/resolver/cache/deno_dir.rs"),
        ]),
        Definition(id: "reactnative", name: "React Native CLI", systemImage: "cube", appBundleIdentifiers: [], folders: [
            Folder("Library/Caches/react-native-cli", .cache, source: "https://github.com/react-native-community/cli/blob/f4c4ef37ccf98e0205d4a8bc5d9f40f24f1120fd/packages/cli-tools/src/cacheManager.ts#L49-L50"),
        ]),
        Definition(id: "expo", name: "Expo", systemImage: "cube", appBundleIdentifiers: [], folders: [
            Folder(".expo/expo-go", .downloads, source: "https://github.com/expo/expo/blob/57441f28c9eea248b6672ffbdcd529b072ea271e/packages/@expo/cli/src/utils/downloadExpoGoAsync.ts#L128-L129"),
            Folder(".expo/versions-cache", .cache, source: "https://github.com/expo/expo/blob/57441f28c9eea248b6672ffbdcd529b072ea271e/packages/@expo/cli/src/api/getVersions.ts#L47"),
            Folder(".expo/ios-simulator-app-cache", .downloads, source: "https://github.com/expo/expo/blob/57441f28c9eea248b6672ffbdcd529b072ea271e/packages/@expo/cli/src/utils/downloadExpoGoAsync.ts#L21"),
            Folder(".expo/android-apk-cache", .downloads, source: "https://github.com/expo/expo/blob/57441f28c9eea248b6672ffbdcd529b072ea271e/packages/@expo/cli/src/utils/downloadExpoGoAsync.ts#L27"),
            Folder(".expo/schema-cache", .cache, source: "https://github.com/expo/expo/blob/57441f28c9eea248b6672ffbdcd529b072ea271e/packages/@expo/cli/src/api/getExpoSchema.ts#L83"),
            Folder(".expo/native-modules-cache", .cache, source: "https://github.com/expo/expo/blob/57441f28c9eea248b6672ffbdcd529b072ea271e/packages/@expo/cli/src/api/getNativeModuleVersions.ts#L35"),
        ]),
        Definition(id: "nx", name: "Nx", systemImage: "cube", appBundleIdentifiers: [], folders: [
            // One workspace's `cache` and `databases`, named by 16 hex digits of a hash. They go together: Nx
            // answers a cache hit from the database alone, and a database without its cache restores nothing.
            Folder(".nx/" + String(repeating: "[0-9a-f]", count: 16), .buildData, source: "https://github.com/nrwl/nx/blob/ead04276f840b920ffab97eb3f809fef2baf130b/packages/nx/src/utils/cache-directory.ts"),
        ]),
        // The package manager versions Corepack downloaded, and not `lastKnownGood.json` beside them, which holds
        // the ones a person chose.
        Definition(id: "corepack", name: "Corepack", systemImage: "cube", appBundleIdentifiers: [], folders: [
            Folder(".cache/node/corepack/v1", .downloads, source: "https://github.com/nodejs/corepack/blob/d4dcb1f89741603e776bba9d457425750fa26987/sources/folderUtils.ts"),
        ]),
        Definition(id: "nvm", name: "nvm", systemImage: "cube", appBundleIdentifiers: [], folders: [
            Folder(".nvm/.cache", .downloads, source: "https://github.com/nvm-sh/nvm/blob/a8bb4974008be929325ae286335702f1a84c5854/nvm.sh#L3519-L3521"),
        ]),
        Definition(id: "prisma", name: "Prisma", systemImage: "cube", appBundleIdentifiers: [], folders: [
            Folder(".cache/prisma", .downloads, source: "https://github.com/prisma/prisma/blob/e92bc46e8fff73e3985f86f23393b7e3f0e90010/packages/fetch-engine/src/utils.ts#L38-L40"),
        ]),
        Definition(id: "playwright", name: "Playwright", systemImage: "globe", appBundleIdentifiers: [], folders: [
            Folder("Library/Caches/ms-playwright", .environments, source: "https://github.com/microsoft/playwright/blob/7ad3fba1aad9471c7e46d67a11b0e710a5d77ea8/docs/src/browsers.md#L958"),
            // A browser's profile and a run's artifacts, which Playwright removes when the browser closes.
            Folder(
                "playwright_*dev_profile-*/", .cache,
                source: "https://github.com/microsoft/playwright/blob/7ad3fba1aad9471c7e46d67a11b0e710a5d77ea8/packages/playwright-core/src/server/browserType.ts#L171",
                base: .userTemporary
            ),
            Folder(
                "playwright-artifacts-*/", .cache,
                source: "https://github.com/microsoft/playwright/blob/7ad3fba1aad9471c7e46d67a11b0e710a5d77ea8/packages/playwright-core/src/server/browserType.ts#L161",
                base: .userTemporary
            ),
        ]),
        Definition(id: "playwrightgo", name: "Playwright for Go", systemImage: "globe", appBundleIdentifiers: [], folders: [
            Folder("Library/Caches/ms-playwright-go", .environments, source: "https://github.com/playwright-community/playwright-go/blob/775648cd1805851a893029e5eed1c8a0962b4e30/run.go#L370-L372"),
        ]),
        // The drivers and browsers Selenium Manager keeps, and not `se-config.toml`, its settings, beside them.
        Definition(id: "selenium", name: "Selenium Manager", systemImage: "globe", appBundleIdentifiers: [], folders: [
            Folder(".cache/selenium/*/", .downloads, source: "https://github.com/SeleniumHQ/seleniumhq.github.io/blob/19cbf6d68fcdcb25d26baca4aaa7979b20b4d2b0/website_and_docs/content/documentation/selenium_manager.en.md#L34"),
        ]),
        Definition(id: "cypress", name: "Cypress", systemImage: "globe", appBundleIdentifiers: [], folders: [
            Folder("Library/Caches/Cypress", .environments, source: "https://github.com/cypress-io/cypress-documentation/blob/a60694ce7ee13b052668db29e0b068161d06ca13/docs/app/get-started/advanced-installation.mdx#L615"),
        ]),
        Definition(id: "puppeteer", name: "Puppeteer", systemImage: "globe", appBundleIdentifiers: [], folders: [
            Folder(".cache/puppeteer", .environments, source: "https://github.com/puppeteer/puppeteer/blob/2e45a3af43231cd658285e4da5e7f53e40f24edf/packages/puppeteer/src/getConfiguration.ts#L162-L165"),
        ]),
        Definition(id: "electron", name: "Electron", systemImage: "cube", appBundleIdentifiers: [], folders: [
            Folder("Library/Caches/electron", .downloads, source: "https://github.com/electron/get/blob/53178fdcbd62f0e229a4f9695632003637c0f35e/README.md#L123"),
            Folder("Library/Caches/electron-builder", .downloads, source: "https://github.com/electron-userland/electron-builder/blob/ec9135d0626879479ffa4235006f06b14375cc43/website/docs/environment-variables.md#L166"),
            Folder(".electron-gyp", .downloads, source: "https://github.com/electron/rebuild/blob/8b14ce89664a4d341afebb0e5964e912d4453b7f/src/constants.ts#L4"),
        ]),
        Definition(id: "nodegyp", name: "node-gyp", systemImage: "cube", appBundleIdentifiers: [], folders: [
            Folder("Library/Caches/node-gyp", .downloads, source: "https://github.com/nodejs/node-gyp/blob/399f6faedf5abc1eb791678e0a03a91d3fef12aa/bin/node-gyp.js#L25"),
            Folder(".node-gyp", .downloads, source: "https://github.com/nodejs/node-gyp/blob/399f6faedf5abc1eb791678e0a03a91d3fef12aa/CHANGELOG.md#v500-2019-06-13"),
        ]),
        Definition(id: "typescript", name: "TypeScript", systemImage: "cube", appBundleIdentifiers: [], folders: [
            Folder("Library/Caches/typescript", .downloads, source: "https://github.com/microsoft/TypeScript/blob/50d70a3f5f453a79a4323b263165da51f656a4e3/tsc/internal/vfs/osvfs/os.go#L191-L204"),
        ]),
        // Python
        Definition(id: "pip", name: "pip", systemImage: "chevron.left.forwardslash.chevron.right", appBundleIdentifiers: [], folders: [
            Folder("Library/Caches/pip", .downloads, source: "https://github.com/pypa/pip/blob/a7002c9771a6c3f0317a4e6b9fbdcd22e643f7b6/docs/html/topics/caching.md#L84-L88"),
        ]),
        Definition(id: "poetry", name: "Poetry", systemImage: "chevron.left.forwardslash.chevron.right", appBundleIdentifiers: [], folders: [
            Folder("Library/Caches/pypoetry/cache", .downloads, source: "https://github.com/python-poetry/poetry/blob/d4fd21e4711ae948f04e18a1736d9ee85b590e87/src/poetry/config/config.py#L283-L284"),
            Folder("Library/Caches/pypoetry/artifacts", .downloads, source: "https://github.com/python-poetry/poetry/blob/d4fd21e4711ae948f04e18a1736d9ee85b590e87/src/poetry/config/config.py#L287-L288"),
            Folder("Library/Caches/pypoetry/virtualenvs", .environments, source: "https://github.com/python-poetry/poetry/blob/d4fd21e4711ae948f04e18a1736d9ee85b590e87/docs/configuration.md#L631-L639"),
        ]),
        Definition(id: "uv", name: "uv", systemImage: "chevron.left.forwardslash.chevron.right", appBundleIdentifiers: [], folders: [
            Folder(".cache/uv", .environments, source: "https://github.com/astral-sh/uv/blob/46b84fd0bfec23b72f29e8e2185ba68a65052f48/docs/concepts/cache.md#L193-L194"),
        ]),
        Definition(id: "precommit", name: "pre-commit", systemImage: "chevron.left.forwardslash.chevron.right", appBundleIdentifiers: [], folders: [
            Folder(".cache/pre-commit", .cache, source: "https://github.com/pre-commit/pre-commit.com/blob/1ac27279528630e26a635ade73f8ee3c5a7cc564/sections/advanced.md#L773"),
        ]),
        Definition(id: "pipenv", name: "Pipenv", systemImage: "chevron.left.forwardslash.chevron.right", appBundleIdentifiers: [], folders: [
            Folder("Library/Caches/pipenv", .downloads, source: "https://github.com/pypa/pipenv/blob/226bc1342043f387eec027fb07a8254768b3f718/pipenv/environments.py#L109-L110"),
            Folder(".local/share/virtualenvs", .environments, source: "https://github.com/pypa/pipenv/blob/226bc1342043f387eec027fb07a8254768b3f718/docs/virtualenv.md#L25"),
        ]),
        Definition(id: "virtualenvwrapper", name: "virtualenvwrapper", systemImage: "chevron.left.forwardslash.chevron.right", appBundleIdentifiers: [], folders: [
            // The environments, not the hook scripts virtualenvwrapper keeps beside them: a pattern that ends in `/`
            // matches folders only.
            Folder(".virtualenvs/*/", .environments, source: "https://github.com/python-virtualenvwrapper/virtualenvwrapper/blob/e938940847c071ce383e5ad3b10d443228cc434e/docs/source/install.rst"),
        ]),
        Definition(id: "conda", name: "Conda", systemImage: "chevron.left.forwardslash.chevron.right", appBundleIdentifiers: [], folders: [
            Folder("miniconda3/pkgs", .environments, source: "https://www.anaconda.com/docs/getting-started/miniconda/install/mac-cli-install"),
            Folder("anaconda3/pkgs", .environments, source: "https://www.anaconda.com/docs/getting-started/anaconda/install/mac-cli-install"),
            Folder(".conda/pkgs", .environments, source: "https://github.com/conda/conda/blob/febc565ad11d3c000f03744acfc33aa0acaec236/conda/base/context.py#L834-L847"),
            Folder("miniforge3/pkgs", .environments, source: "https://github.com/conda-forge/miniforge/blob/90db2535aae8465c04f7ac50f00c9a54b27712bc/README.md#L53"),
        ]),
        Definition(id: "mamba", name: "mamba & micromamba", systemImage: "chevron.left.forwardslash.chevron.right", appBundleIdentifiers: [], folders: [
            Folder("micromamba/pkgs", .environments, source: "https://github.com/mamba-org/mamba/blob/661c41ab21d492b4f39e5e6f2af685ee15d2541e/libmamba/src/api/configuration.cpp#L1011-L1015"),
            Folder(".mamba/pkgs", .environments, source: "https://github.com/mamba-org/mamba/blob/661c41ab21d492b4f39e5e6f2af685ee15d2541e/libmamba/src/api/configuration.cpp#L1015"),
        ]),
        Definition(id: "pixi", name: "pixi", systemImage: "chevron.left.forwardslash.chevron.right", appBundleIdentifiers: [], folders: [
            Folder("Library/Caches/rattler", .downloads, source: "https://github.com/prefix-dev/pixi/blob/22c8af58b3068292bdad7e995482495fa26f8691/docs/workspace/environment.md#L171-L179"),
        ]),
        Definition(id: "pdm", name: "PDM", systemImage: "chevron.left.forwardslash.chevron.right", appBundleIdentifiers: [], folders: [
            Folder("Library/Caches/pdm/http", .cache, source: "https://github.com/pdm-project/pdm/blob/390bb6d1e446380d2a4412addd469a38736d1ade/src/pdm/environments/base.py#L140"),
            Folder("Library/Caches/pdm/wheels", .downloads, source: "https://github.com/pdm-project/pdm/blob/390bb6d1e446380d2a4412addd469a38736d1ade/src/pdm/project/core.py#L912-L944"),
            Folder("Library/Caches/pdm/metadata", .cache, source: "https://github.com/pdm-project/pdm/blob/390bb6d1e446380d2a4412addd469a38736d1ade/src/pdm/project/core.py#L912-L944"),
            Folder("Library/Caches/pdm/hashes", .cache, source: "https://github.com/pdm-project/pdm/blob/390bb6d1e446380d2a4412addd469a38736d1ade/src/pdm/project/core.py#L912-L944"),
            // PDM's `packages` is the store projects link their installed packages into, so it is never selected.
            Folder("Library/Caches/pdm/packages", .environments, source: "https://github.com/pdm-project/pdm/blob/390bb6d1e446380d2a4412addd469a38736d1ade/docs/usage/config.md#L252"),
            Folder("Library/Logs/pdm", .logs, source: "https://github.com/pdm-project/pdm/blob/390bb6d1e446380d2a4412addd469a38736d1ade/src/pdm/project/config.py#L116-L120"),
        ]),
        Definition(id: "hatch", name: "Hatch", systemImage: "chevron.left.forwardslash.chevron.right", appBundleIdentifiers: [], folders: [
            Folder("Library/Caches/hatch", .cache, source: "https://github.com/pypa/hatch/blob/7c26ebeaf8b83f5f0374a2545bb15e36c87db0d0/docs/config/hatch.md#L140-L146"),
        ]),
        Definition(id: "pipx", name: "pipx", systemImage: "chevron.left.forwardslash.chevron.right", appBundleIdentifiers: [], folders: [
            Folder("Library/Caches/pipx", .cache, source: "https://github.com/pypa/pipx/blob/b09807b86e0844d92f3f92216fcdfcf607161c6c/src/pipx/paths.py#L76-L77"),
            Folder("Library/Logs/pipx", .logs, source: "https://github.com/pypa/pipx/blob/b09807b86e0844d92f3f92216fcdfcf607161c6c/src/pipx/paths.py#L126"),
        ]),
        Definition(id: "piptools", name: "pip-tools", systemImage: "chevron.left.forwardslash.chevron.right", appBundleIdentifiers: [], folders: [
            Folder("Library/Caches/pip-tools", .cache, source: "https://github.com/jazzband/pip-tools/blob/28538e4385d270b8500cc5e2088294cf13456aee/piptools/locations.py#L5-L6"),
        ]),
        Definition(id: "black", name: "Black", systemImage: "chevron.left.forwardslash.chevron.right", appBundleIdentifiers: [], folders: [
            Folder("Library/Caches/black", .cache, source: "https://github.com/psf/black/blob/93e5c8204c0340403c925a3bf7b747bf7817aaab/src/black/cache.py#L42-L43"),
        ]),
        Definition(id: "jedi", name: "Jedi & Parso", systemImage: "chevron.left.forwardslash.chevron.right", appBundleIdentifiers: [], folders: [
            Folder("Library/Caches/Jedi", .cache, source: "https://github.com/davidhalter/jedi/blob/2e3e9057078a328d846aff43d88e00c13d7cccd5/jedi/settings.py#L77-L78"),
            Folder("Library/Caches/Parso", .cache, source: "https://github.com/davidhalter/parso/blob/b26da16316da46e4770d589ed5f8d404531a22af/parso/cache.py#L69-L70"),
        ]),
        Definition(id: "pyinstaller", name: "PyInstaller", systemImage: "chevron.left.forwardslash.chevron.right", appBundleIdentifiers: [], folders: [
            Folder("Library/Application Support/pyinstaller/bincache*/", .cache, source: "https://github.com/pyinstaller/pyinstaller/blob/cea3915d00801b4f45c9f89636ee0ff0d4eaa988/PyInstaller/configure.py#L53-L71"),
        ]),
        // Only the package files `pyenv install` keeps, never `versions`, the Pythons it installed.
        Definition(id: "pyenv", name: "pyenv", systemImage: "chevron.left.forwardslash.chevron.right", appBundleIdentifiers: [], folders: [
            Folder(".pyenv/cache", .downloads, source: "https://github.com/pyenv/pyenv/blob/f9d17bfc06ccbda37edd84df99a4f50d8d7d2a4a/plugins/python-build/bin/pyenv-install#L235-L238"),
        ]),
        // Rust and Go
        // Only what rustup downloaded, which `rustup update` empties itself, never the toolchains it installed.
        Definition(id: "rustup", name: "rustup", systemImage: "gearshape.2", appBundleIdentifiers: [], folders: [
            Folder(".rustup/downloads", .downloads, source: "https://github.com/rust-lang/rustup/blob/b46db5ea94c1024c7cd2e7133a7f9b2ec1927478/src/cli/rustup_mode.rs#L1203-L1205"),
        ]),
        Definition(id: "cargo", name: "Cargo", systemImage: "gearshape.2", appBundleIdentifiers: [], folders: [
            Folder(".cargo/registry/cache", .downloads, source: "https://github.com/rust-lang/cargo/blob/bb2126cffae48394a37db8728dc50a17bbfe54d4/doc/book/src/guide/cargo-home.md#L47-L48"),
            Folder(".cargo/registry/index", .downloads, source: "https://github.com/rust-lang/cargo/blob/bb2126cffae48394a37db8728dc50a17bbfe54d4/doc/book/src/guide/cargo-home.md#L44-L45"),
            Folder(".cargo/registry/src", .downloads, source: "https://github.com/rust-lang/cargo/blob/bb2126cffae48394a37db8728dc50a17bbfe54d4/doc/book/src/guide/cargo-home.md#L50-L51"),
            Folder(".cargo/git/checkouts", .downloads, source: "https://github.com/rust-lang/cargo/blob/bb2126cffae48394a37db8728dc50a17bbfe54d4/doc/book/src/guide/cargo-home.md#L36-L37"),
            Folder(".cargo/git/db", .downloads, source: "https://github.com/rust-lang/cargo/blob/bb2126cffae48394a37db8728dc50a17bbfe54d4/doc/book/src/guide/cargo-home.md#L33-L34"),
        ]),
        Definition(id: "go", name: "Go", systemImage: "chevron.left.forwardslash.chevron.right", appBundleIdentifiers: [], folders: [
            Folder("Library/Caches/go-build", .buildData, source: "https://github.com/golang/go/blob/6f5c275ebdc454197fff5f1496521c8f81e20eef/src/cmd/go/alldocs.go#L2372-L2373", movedBy: .goBuildCache),
            Folder("go/pkg/mod/cache/download", .downloads, source: "https://github.com/golang/website/blob/32881aa55f0d81413cda4fe43e0236d0cae2b2ec/_content/ref/mod.md#L4020-L4028", movedBy: .goModuleCache(inside: "cache/download")),
            Folder("go/pkg/mod/cache/vcs", .downloads, source: "https://github.com/golang/website/blob/32881aa55f0d81413cda4fe43e0236d0cae2b2ec/_content/ref/mod.md#L4088-L4095", movedBy: .goModuleCache(inside: "cache/vcs")),
        ]),
        Definition(id: "sccache", name: "sccache", systemImage: "gearshape.2", appBundleIdentifiers: [], folders: [
            Folder("Library/Caches/Mozilla.sccache", .buildData, source: "https://github.com/mozilla/sccache/blob/50b329680bec2c01e84bc7b78a5a5cc41cffee82/docs/Local.md#L3"),
        ]),
        Definition(id: "gopls", name: "gopls", systemImage: "chevron.left.forwardslash.chevron.right", appBundleIdentifiers: [], folders: [
            Folder("Library/Caches/gopls", .cache, source: "https://github.com/golang/tools/blob/3f3efb7c3b31192232c67403b23a00bfcdbc3eec/gopls/internal/filecache/filecache.go#L430-L438"),
        ]),
        Definition(id: "golangcilint", name: "golangci-lint", systemImage: "chevron.left.forwardslash.chevron.right", appBundleIdentifiers: [], folders: [
            Folder("Library/Caches/golangci-lint", .cache, source: "https://github.com/golangci/golangci-lint/blob/efac294f10051803f88873bd278f5675e781b8f5/docs/content/docs/configuration/cli.md#L63"),
        ]),
        Definition(id: "staticcheck", name: "Staticcheck", systemImage: "chevron.left.forwardslash.chevron.right", appBundleIdentifiers: [], folders: [
            Folder("Library/Caches/staticcheck", .cache, source: "https://github.com/dominikh/go-tools/blob/6cb65e58a558452b52f57cb43267ff9df669a77a/lintcmd/cache/default.go#L80-L85"),
        ]),
        // JVM and Android
        Definition(id: "gradle", name: "Gradle", systemImage: "cup.and.saucer", appBundleIdentifiers: [], folders: [
            Folder(".gradle/caches", .downloads, source: "https://github.com/gradle/gradle/blob/07329ddefeabecfd93dc018ac91840f3efe542f2/platforms/documentation/docs/src/docs/userguide/reference/runtime-configuration/directory_layout.adoc#L40-L53"),
            Folder(".gradle/wrapper/dists", .downloads, source: "https://github.com/gradle/gradle/blob/07329ddefeabecfd93dc018ac91840f3efe542f2/platforms/documentation/docs/src/docs/userguide/reference/runtime-configuration/directory_layout.adoc#L52"),
            Folder(".gradle/daemon", .cache, source: "https://github.com/gradle/gradle/blob/07329ddefeabecfd93dc018ac91840f3efe542f2/platforms/documentation/docs/src/docs/userguide/reference/runtime-configuration/directory_layout.adoc#L49"),
            Folder(".gradle/notifications", .cache, source: "https://github.com/gradle/gradle/blob/07329ddefeabecfd93dc018ac91840f3efe542f2/platforms/core-runtime/gradle-cli/src/main/java/org/gradle/launcher/cli/WelcomeMessageAction.java#L121-L126"),
            Folder(".gradle/workers", .cache, source: "https://github.com/gradle/gradle/blob/07329ddefeabecfd93dc018ac91840f3efe542f2/platforms/core-execution/worker-main/src/main/java/org/gradle/process/internal/worker/child/DefaultWorkerDirectoryProvider.java#L31-L38"),
        ]),
        Definition(id: "maven", name: "Maven", systemImage: "cup.and.saucer", appBundleIdentifiers: [], folders: [
            // `mvn install` puts the person's own modules here, which exist nowhere else (Maven's introduction to
            // repositories), while Gradle, Ivy, sbt and NuGet keep only what they download again by themselves.
            Folder(".m2/repository", .environments, source: "https://github.com/apache/maven/blob/b501f5357d5ee4bc26e674bf289fbccd914ff309/api/maven-api-settings/src/main/mdo/settings.mdo#L110"),
            Folder(".m2/wrapper/dists", .downloads, source: "https://github.com/apache/maven-wrapper/blob/24915d789fc9b6e6316c3d6806ca94782fc2c713/maven-wrapper/src/site/markdown/index.md#L29"),
        ]),
        Definition(id: "sbt", name: "sbt & Coursier", systemImage: "cup.and.saucer", appBundleIdentifiers: [], folders: [
            Folder(".sbt/boot", .downloads, source: "https://github.com/sbt/website/blob/5d50117e6ecf26a7557809a3d0c623c44cfc6d8c/src/reference/01-Faq/00.md#L283-L284"),
            Folder(".ivy2/cache", .downloads, source: "https://github.com/apache/ant-ivy/blob/e82f1882b1fdc580fc1c5dcd0935115ad963a747/asciidoc/settings/caches.adoc#L48"),
            // Only the cache. `Coursier/jvm` beside it holds the JVMs `cs java` installed, which `JAVA_HOME`
            // points at (https://get-coursier.io/docs/cache and https://get-coursier.io/docs/cli-java).
            Folder("Library/Caches/Coursier/v1", .downloads, source: "https://github.com/coursier/coursier/blob/d3006393e44af0dc0165813f262de2de51e17a46/doc/docs/cache.md#L30"),
            Folder(".coursier/cache/v1", .downloads, source: "https://github.com/coursier/coursier/blob/d3006393e44af0dc0165813f262de2de51e17a46/doc/docs/cache.md#L48-L54"),
            Folder("Library/Caches/sbt", .buildData, source: "https://github.com/sbt/sbt/blob/f4618946c5b7055083f8c74bf84e4d1ad5e6a1e9/main/src/main/scala/sbt/internal/SysProp.scala#L231-L245"),
        ]),
        Definition(id: "konan", name: "Kotlin/Native", systemImage: "cup.and.saucer", appBundleIdentifiers: [], folders: [
            Folder(".konan/dependencies", .downloads, source: "https://github.com/JetBrains/kotlin/blob/4e93a0a3323a27fe7064103af6eb76e54afe16eb/native/utils/src/org/jetbrains/kotlin/konan/util/DependencyDirectories.kt#L12-L32"),
            Folder(".konan/cache", .buildData, source: "https://github.com/JetBrains/kotlin/blob/4e93a0a3323a27fe7064103af6eb76e54afe16eb/native/utils/src/org/jetbrains/kotlin/konan/util/DependencyDirectories.kt#L13-L36"),
        ]),
        // Other languages
        Definition(id: "dart", name: "Dart & Flutter", systemImage: "chevron.left.forwardslash.chevron.right", appBundleIdentifiers: [], folders: [
            // Every Dart project names its packages' folders here in `.dart_tool/package_config.json`, and pub's own
            // `cache clean` warns that each project needs `pub get` again, so they are never selected.
            Folder(".pub-cache/hosted", .environments, source: "https://github.com/dart-lang/site-www/blob/0590fb830cc9d02c97d4c71777f902c3a7936d78/src/content/tools/pub/cmd/pub-get.md#L99-L100"),
            Folder(".pub-cache/git", .environments, source: "https://github.com/dart-lang/pub/blob/90bb91c90cc8edc0d32693f16a4075be6b1e4fce/lib/src/system_cache.dart#L48"),
            Folder(".dartServer/.analysis-driver", .cache, source: "https://github.com/dart-lang/sdk/blob/5c1f33f9ea7d580c0ab58d913da7daa7dafee77a/pkg/analysis_server/lib/src/analysis_server.dart#L737-L741"),
        ]),
        Definition(id: "composer", name: "Composer", systemImage: "chevron.left.forwardslash.chevron.right", appBundleIdentifiers: [], folders: [
            Folder("Library/Caches/composer", .downloads, source: "https://github.com/composer/composer/blob/e9e8482d8331657123e5c4cad44c7fb36137868e/doc/06-config.md#L1241-L1247"),
            Folder(".composer/cache", .downloads, source: "https://github.com/composer/composer/blob/e9e8482d8331657123e5c4cad44c7fb36137868e/src/Composer/Factory.php#L122-L128"),
        ]),
        Definition(id: "cpan", name: "CPAN", systemImage: "shippingbox", appBundleIdentifiers: [], folders: [
            Folder(".cpan/build", .buildData, source: "https://github.com/andk/cpanpm/blob/c01e087f4a32641c4b4118024666d7d790d9f81c/lib/CPAN/FirstTime.pm#L930"),
        ]),
        Definition(id: "rubygems", name: "RubyGems & Bundler", systemImage: "shippingbox", appBundleIdentifiers: [], folders: [
            Folder(".gem/ruby/*/cache", .downloads, source: "https://github.com/ruby/rubygems/blob/6e65a1be83f3e6bc6384dba21d6eafa85822f8f1/lib/rubygems/specification.rb#L1659-L1660"),
            Folder(".gem/specs", .cache, source: "https://github.com/ruby/rubygems/blob/6e65a1be83f3e6bc6384dba21d6eafa85822f8f1/lib/rubygems/defaults.rb#L23-L30"),
            Folder(".cache/gem/gems", .downloads, source: "https://github.com/ruby/rubygems/blob/6e65a1be83f3e6bc6384dba21d6eafa85822f8f1/lib/rubygems/defaults.rb#L151-L158"),
            Folder(".cache/gem/specs", .cache, source: "https://github.com/ruby/rubygems/blob/6e65a1be83f3e6bc6384dba21d6eafa85822f8f1/lib/rubygems/defaults.rb#L26-L28"),
            Folder(".bundle/cache", .downloads, source: "https://github.com/ruby/rubygems/blob/6e65a1be83f3e6bc6384dba21d6eafa85822f8f1/lib/bundler.rb#L284-L303"),
            Folder(".local/share/gem/ruby/*/cache", .downloads, source: "https://github.com/ruby/rubygems/blob/6e65a1be83f3e6bc6384dba21d6eafa85822f8f1/lib/rubygems/defaults.rb#L103-L109"),
        ]),
        // Only the package files `rbenv install` keeps, never `versions`, the Rubies it installed.
        Definition(id: "rbenv", name: "rbenv", systemImage: "shippingbox", appBundleIdentifiers: [], folders: [
            Folder(".rbenv/cache", .downloads, source: "https://github.com/rbenv/ruby-build/blob/db86e6ddd6d3b1d8715d005b65fab0c3f2804fdd/bin/rbenv-install#L209-L212"),
        ]),
        Definition(id: "nuget", name: "NuGet", systemImage: "shippingbox", appBundleIdentifiers: [], folders: [
            Folder(".nuget/packages", .downloads, source: "https://github.com/NuGet/docs.microsoft.com-nuget/blob/3ecef866b0bc71c8f9ee0b5673dee4b210f8eff1/docs/consume-packages/managing-the-global-packages-and-cache-folders.md#L17"),
            Folder(".local/share/NuGet/v3-cache", .cache, source: "https://github.com/NuGet/docs.microsoft.com-nuget/blob/3ecef866b0bc71c8f9ee0b5673dee4b210f8eff1/docs/consume-packages/managing-the-global-packages-and-cache-folders.md#L18"),
            Folder(".local/share/NuGet/plugins-cache", .cache, source: "https://github.com/NuGet/docs.microsoft.com-nuget/blob/3ecef866b0bc71c8f9ee0b5673dee4b210f8eff1/docs/consume-packages/managing-the-global-packages-and-cache-folders.md#L20"),
        ]),
        Definition(id: "julia", name: "Julia", systemImage: "chevron.left.forwardslash.chevron.right", appBundleIdentifiers: [], folders: [
            Folder(".julia/artifacts", .downloads, source: "https://github.com/JuliaLang/julia/blob/70432117499f8ac209cb19a904f53611c8893e80/base/initdefs.jl#L111"),
            Folder(".julia/clones", .downloads, source: "https://github.com/JuliaLang/julia/blob/70432117499f8ac209cb19a904f53611c8893e80/base/initdefs.jl#L112"),
            Folder(".julia/compiled", .buildData, source: "https://github.com/JuliaLang/julia/blob/70432117499f8ac209cb19a904f53611c8893e80/base/initdefs.jl#L114"),
            Folder(".julia/scratchspaces", .cache, source: "https://github.com/JuliaLang/julia/blob/70432117499f8ac209cb19a904f53611c8893e80/base/initdefs.jl#L120"),
        ]),
        Definition(id: "nix", name: "Nix", systemImage: "shippingbox", appBundleIdentifiers: [], folders: [
            Folder(".cache/nix", .cache, source: "https://github.com/NixOS/nix/blob/e8280775f307a94ca82cea193cfcc14c0d56232a/src/libutil/include/nix/util/users.hh#L28-L30"),
        ]),
        Definition(id: "rubocop", name: "RuboCop", systemImage: "chevron.left.forwardslash.chevron.right", appBundleIdentifiers: [], folders: [
            Folder(".cache/rubocop_cache", .cache, source: "https://github.com/rubocop/rubocop/blob/ec1080049ab773c5b5cca42cf963349be293c0a7/lib/rubocop/cache_config.rb#L23-L26"),
        ]),
        Definition(id: "hex", name: "Hex", systemImage: "shippingbox", appBundleIdentifiers: [], folders: [
            Folder(".hex/packages", .downloads, source: "https://github.com/hexpm/hex/blob/8ce21f32a72de3995ae142d57ca3dffb0d46e645/lib/hex/scm.ex#L8"),
            Folder(".hex/cache.ets", .cache, source: "https://github.com/hexpm/hex/blob/8ce21f32a72de3995ae142d57ca3dffb0d46e645/lib/hex/registry/server.ex#L8"),
        ]),
        Definition(id: "rebar3", name: "rebar3", systemImage: "shippingbox", appBundleIdentifiers: [], folders: [
            Folder(".cache/rebar3/hex", .downloads, source: "https://github.com/erlang/rebar3/blob/f23f21b5166613b555cead1fc43135a411e90451/apps/rebar/src/rebar_packages.erl#L159-L160"),
        ]),
        Definition(id: "gleam", name: "Gleam", systemImage: "shippingbox", appBundleIdentifiers: [], folders: [
            Folder("Library/Caches/gleam/hex/hexpm/packages", .downloads, source: "https://github.com/gleam-lang/gleam/blob/acbdbe880f3d26fb52e8ba5ba55d5e6d246b4706/compiler-core/src/paths.rs#L171-L183"),
        ]),
        Definition(id: "cabal", name: "Cabal", systemImage: "shippingbox", appBundleIdentifiers: [], folders: [
            Folder(".cache/cabal", .downloads, source: "https://github.com/haskell/cabal/blob/cdb488e5ef41005cb1fa9a534708a459a6e98b2e/doc/config.rst#L112-L115"),
        ]),
        Definition(id: "stack", name: "Haskell Stack", systemImage: "shippingbox", appBundleIdentifiers: [], folders: [
            Folder(".stack/pantry/hackage", .downloads, source: "https://github.com/commercialhaskell/stack/blob/d5effcd3f32e1dc3e6fc352c65938310f3acd675/doc/topics/stack_root.md#L228-L232"),
            Folder(".stack/setup-exe-cache", .buildData, source: "https://github.com/commercialhaskell/stack/blob/d5effcd3f32e1dc3e6fc352c65938310f3acd675/doc/topics/stack_root.md#L277-L284"),
            Folder(".stack/snapshots", .environments, source: "https://github.com/commercialhaskell/stack/blob/d5effcd3f32e1dc3e6fc352c65938310f3acd675/doc/topics/stack_root.md#L312-L318"),
        ]),
        Definition(id: "opam", name: "opam", systemImage: "shippingbox", appBundleIdentifiers: [], folders: [
            Folder(".opam/download-cache", .downloads, source: "https://github.com/ocaml/opam/blob/9b5b02e3097b1d6c870e593488a9bbf2419c90b8/doc/pages/Manual.md#L41"),
        ]),
        Definition(id: "luarocks", name: "LuaRocks", systemImage: "shippingbox", appBundleIdentifiers: [], folders: [
            Folder(".cache/luarocks", .downloads, source: "https://github.com/luarocks/luarocks/blob/2d2cc8eff2f03c23d142f8059146fb241dcf56b5/src/luarocks/core/cfg.lua#L411-L412"),
        ]),
        Definition(id: "renv", name: "renv", systemImage: "shippingbox", appBundleIdentifiers: [], folders: [
            // renv links each project's library into this cache, so it is never selected.
            Folder("Library/Caches/org.R-project.R/R/renv/cache", .environments, source: "https://github.com/rstudio/renv/blob/bde1035a41f0f275d2cf58d255603f8d466879f0/vignettes/package-install.Rmd#L56"),
        ]),
        Definition(id: "clojure", name: "Clojure", systemImage: "chevron.left.forwardslash.chevron.right", appBundleIdentifiers: [], folders: [
            Folder(".gitlibs", .downloads, source: "https://github.com/clojure/tools.gitlibs/blob/a306db607ca0232282870d439f2b676912360e84/README.md#L44"),
            // Only the cache: `.clojure` holds the person's own `deps.edn` and tools beside it.
            Folder(".clojure/.cpcache", .cache, source: "https://github.com/clojure/clojure-site/blob/15d0adc7ccd1dc8aa1c622dc824bef76507c276a/content/reference/clojure_cli.adoc#L490-L504"),
        ]),
        Definition(id: "mise", name: "mise", systemImage: "shippingbox", appBundleIdentifiers: [], folders: [
            Folder("Library/Caches/mise", .cache, source: "https://github.com/jdx/mise/blob/95bd89446f8fd2c62c355317d8567693243cc439/docs/directories.md#L34-L41"),
        ]),
        // Shells
        Definition(id: "zsh", name: "zsh", systemImage: "terminal", appBundleIdentifiers: [], folders: [
            Folder(".zcompdump*", .cache, source: "https://zsh.sourceforge.io/Doc/Release/Completion-System.html#Use-of-compinit"),
        ]),
        // Only the completion scripts plug-ins make again when missing: `dotenv` keeps the files a person allowed
        // beside them in the same cache folder.
        Definition(id: "ohmyzsh", name: "Oh My Zsh", systemImage: "terminal", appBundleIdentifiers: [], folders: [
            Folder(".oh-my-zsh/cache/completions", .cache, source: "https://github.com/ohmyzsh/ohmyzsh/blob/4d4cfc287e9d887b81242c0e431b5f49f9cec5c1/oh-my-zsh.sh#L59-L68"),
        ]),
        // Editors
        // A JetBrains IDE keeps `LocalHistory` beside its caches: the edits it recorded while a project was
        // open, which are in no repository and nowhere else. The cache folders are listed one by one, so
        // `LocalHistory` is never removed with them.
        Definition(id: "jetbrains", name: "JetBrains IDEs", systemImage: "curlybraces", appBundleIdentifiers: withEarlyAccess([
            "com.jetbrains.intellij", "com.jetbrains.intellij.ce", "com.jetbrains.pycharm", "com.jetbrains.pycharm.ce",
            "com.jetbrains.WebStorm", "com.jetbrains.PhpStorm", "com.jetbrains.goland", "com.jetbrains.rubymine",
            "com.jetbrains.CLion", "com.jetbrains.rider", "com.jetbrains.datagrip", "com.jetbrains.AppCode",
            "com.jetbrains.rustrover", "com.jetbrains.dataspell", "com.jetbrains.gateway", "com.jetbrains.writerside",
            "com.jetbrains.mps", "com.google.android.studio",
        ]), folders: [
            Folder("Library/Caches/JetBrains/*/caches", .cache, source: "https://github.com/JetBrains/intellij-community/blob/0e6f75c33cccdcf8097ef9f0a9ca4a2af8c68cd2/platform/vfs-impl/src/com/intellij/openapi/vfs/newvfs/persistent/FSRecords.java#L80"),
            Folder("Library/Caches/JetBrains/*/index", .cache, source: "https://github.com/JetBrains/intellij-community/blob/0e6f75c33cccdcf8097ef9f0a9ca4a2af8c68cd2/platform/util/src/com/intellij/openapi/application/PathManager.java#L648-L651"),
            Folder("Library/Caches/JetBrains/*/tmp", .cache, source: "https://github.com/JetBrains/intellij-community/blob/0e6f75c33cccdcf8097ef9f0a9ca4a2af8c68cd2/platform/util/src/com/intellij/openapi/application/PathManager.java#L634-L636"),
            Folder("Library/Logs/JetBrains", .logs, source: "https://www.jetbrains.com/help/idea/directories-used-by-the-ide-to-store-settings-caches-plugins-and-logs.html"),
        ]),
        Definition(id: "vscode", name: "Visual Studio Code", systemImage: "curlybraces", appBundleIdentifiers: ["com.microsoft.VSCode"], folders: [
            Folder("Library/Application Support/Code/Cache", .cache, source: "https://github.com/electron/electron/blob/df79406cecfd393f38d5a18b83379d4ba85cc29b/shell/browser/net/network_context_service.cc#L94-L95"),
            Folder("Library/Application Support/Code/CachedData", .cache, source: "https://github.com/microsoft/vscode/blob/0817aaa824590067854c361e77eb973a08b3cf48/src/mainImpl.ts#L649-L668"),
            Folder("Library/Application Support/Code/CachedExtensionVSIXs", .downloads, source: "https://github.com/microsoft/vscode/blob/0817aaa824590067854c361e77eb973a08b3cf48/src/vs/platform/environment/common/environmentService.ts#L127"),
            Folder("Library/Application Support/Code/logs", .logs, source: "https://github.com/microsoft/vscode/blob/0817aaa824590067854c361e77eb973a08b3cf48/src/vs/platform/environment/common/environmentService.ts#L73-L79"),
            Folder("Library/Application Support/Code/Code Cache", .cache, source: "https://github.com/chromium/chromium/blob/54cc36437b23cee8aaffa1289c8bc31bf2f520b9/content/browser/storage_partition_impl.cc#L1587-L1595"),
            Folder("Library/Application Support/Code/GPUCache", .cache, source: "https://github.com/chromium/chromium/blob/54cc36437b23cee8aaffa1289c8bc31bf2f520b9/gpu/ipc/common/gpu_disk_cache_type.cc#L46"),
            Folder("Library/Application Support/Code/DawnWebGPUCache", .cache, source: "https://github.com/chromium/chromium/blob/54cc36437b23cee8aaffa1289c8bc31bf2f520b9/gpu/ipc/common/gpu_disk_cache_type.cc#L48"),
            Folder("Library/Application Support/Code/DawnGraphiteCache", .cache, source: "https://github.com/chromium/chromium/blob/54cc36437b23cee8aaffa1289c8bc31bf2f520b9/gpu/ipc/common/gpu_disk_cache_type.cc#L50"),
            Folder("Library/Application Support/Code/CachedProfilesData", .cache, source: "https://github.com/microsoft/vscode/blob/0817aaa824590067854c361e77eb973a08b3cf48/src/vs/platform/userDataProfile/common/userDataProfile.ts#L274"),
            Folder("Library/Application Support/Code/CachedConfigurations", .cache, source: "https://github.com/microsoft/vscode/blob/0817aaa824590067854c361e77eb973a08b3cf48/src/vs/workbench/services/configuration/common/configurationCache.ts#L66"),
            Folder(
                "Library/Application Support/Code/User/workspaceStorage", .projectState, source: "https://github.com/microsoft/vscode/blob/0817aaa824590067854c361e77eb973a08b3cf48/src/vs/platform/storage/electron-main/storageMain.ts#L469-L482",
                rowsDepth: 1, rowsAreProjectState: true
            ),
            Folder("Library/Caches/com.microsoft.VSCode.ShipIt", .downloads, source: "https://github.com/Squirrel/Squirrel.Mac/blob/5c9e2133c09d6f8e2e3c5a45c5b0ffc00448c58a/Squirrel/SQRLUpdater.m#L814-L829"),
        ]),
        Definition(id: "vscodium", name: "VSCodium", systemImage: "curlybraces", appBundleIdentifiers: ["com.vscodium"], folders: [
            Folder("Library/Application Support/VSCodium/Cache", .cache, source: "https://github.com/VSCodium/vscodium/blob/5a73682ca091082675b10c9dc3f348c1d824d94f/docs/migration.md#L23"),
            Folder("Library/Application Support/VSCodium/CachedData", .cache, source: "https://github.com/VSCodium/vscodium/blob/5a73682ca091082675b10c9dc3f348c1d824d94f/docs/migration.md#L23"),
            Folder("Library/Application Support/VSCodium/CachedExtensionVSIXs", .downloads, source: "https://github.com/VSCodium/vscodium/blob/5a73682ca091082675b10c9dc3f348c1d824d94f/docs/migration.md#L23"),
            Folder("Library/Caches/com.vscodium", .cache, source: "https://developer.apple.com/documentation/foundation/filemanager/searchpathdirectory/cachesdirectory"),
            Folder("Library/Application Support/VSCodium/logs", .logs, source: "https://github.com/microsoft/vscode/blob/0817aaa824590067854c361e77eb973a08b3cf48/src/vs/platform/environment/common/environmentService.ts#L73-L79"),
            Folder("Library/Application Support/VSCodium/Code Cache", .cache, source: "https://github.com/chromium/chromium/blob/54cc36437b23cee8aaffa1289c8bc31bf2f520b9/content/browser/storage_partition_impl.cc#L1587-L1595"),
            Folder("Library/Application Support/VSCodium/GPUCache", .cache, source: "https://github.com/chromium/chromium/blob/54cc36437b23cee8aaffa1289c8bc31bf2f520b9/gpu/ipc/common/gpu_disk_cache_type.cc#L46"),
            Folder("Library/Application Support/VSCodium/DawnWebGPUCache", .cache, source: "https://github.com/chromium/chromium/blob/54cc36437b23cee8aaffa1289c8bc31bf2f520b9/gpu/ipc/common/gpu_disk_cache_type.cc#L48"),
            Folder("Library/Application Support/VSCodium/DawnGraphiteCache", .cache, source: "https://github.com/chromium/chromium/blob/54cc36437b23cee8aaffa1289c8bc31bf2f520b9/gpu/ipc/common/gpu_disk_cache_type.cc#L50"),
            Folder("Library/Application Support/VSCodium/CachedProfilesData", .cache, source: "https://github.com/microsoft/vscode/blob/0817aaa824590067854c361e77eb973a08b3cf48/src/vs/platform/userDataProfile/common/userDataProfile.ts#L274"),
            Folder("Library/Application Support/VSCodium/CachedConfigurations", .cache, source: "https://github.com/microsoft/vscode/blob/0817aaa824590067854c361e77eb973a08b3cf48/src/vs/workbench/services/configuration/common/configurationCache.ts#L66"),
            Folder(
                "Library/Application Support/VSCodium/User/workspaceStorage", .projectState, source: "https://github.com/microsoft/vscode/blob/0817aaa824590067854c361e77eb973a08b3cf48/src/vs/platform/storage/electron-main/storageMain.ts#L469-L482",
                rowsDepth: 1, rowsAreProjectState: true
            ),
            Folder("Library/Caches/com.vscodium.ShipIt", .downloads, source: "https://github.com/Squirrel/Squirrel.Mac/blob/5c9e2133c09d6f8e2e3c5a45c5b0ffc00448c58a/Squirrel/SQRLShipItLauncher.m#L25-L26"),
        ]),
        Definition(id: "cursor", name: "Cursor", systemImage: "curlybraces", appBundleIdentifiers: ["com.todesktop.230313mzl4w4u92"], folders: [
            Folder("Library/Application Support/Cursor/Cache", .cache, source: "https://github.com/microsoft/vscode/blob/0817aaa824590067854c361e77eb973a08b3cf48/src/vs/platform/environment/node/userDataPath.ts#L95-L105"),
            Folder("Library/Application Support/Cursor/CachedData", .cache, source: "https://github.com/microsoft/vscode/blob/0817aaa824590067854c361e77eb973a08b3cf48/src/mainImpl.ts#L649-L668"),
            Folder("Library/Application Support/Cursor/logs", .logs, source: "https://github.com/microsoft/vscode/blob/0817aaa824590067854c361e77eb973a08b3cf48/src/vs/platform/environment/common/environmentService.ts#L73-L79"),
            Folder("Library/Application Support/Cursor/Code Cache", .cache, source: "https://github.com/chromium/chromium/blob/54cc36437b23cee8aaffa1289c8bc31bf2f520b9/content/browser/storage_partition_impl.cc#L1587-L1595"),
            Folder("Library/Application Support/Cursor/GPUCache", .cache, source: "https://github.com/chromium/chromium/blob/54cc36437b23cee8aaffa1289c8bc31bf2f520b9/gpu/ipc/common/gpu_disk_cache_type.cc#L46"),
            Folder("Library/Application Support/Cursor/DawnWebGPUCache", .cache, source: "https://github.com/chromium/chromium/blob/54cc36437b23cee8aaffa1289c8bc31bf2f520b9/gpu/ipc/common/gpu_disk_cache_type.cc#L48"),
            Folder("Library/Application Support/Cursor/DawnGraphiteCache", .cache, source: "https://github.com/chromium/chromium/blob/54cc36437b23cee8aaffa1289c8bc31bf2f520b9/gpu/ipc/common/gpu_disk_cache_type.cc#L50"),
            Folder("Library/Application Support/Cursor/CachedExtensionVSIXs", .downloads, source: "https://github.com/microsoft/vscode/blob/0817aaa824590067854c361e77eb973a08b3cf48/src/vs/platform/environment/common/environmentService.ts#L127"),
            Folder("Library/Application Support/Cursor/CachedProfilesData", .cache, source: "https://github.com/microsoft/vscode/blob/0817aaa824590067854c361e77eb973a08b3cf48/src/vs/platform/userDataProfile/common/userDataProfile.ts#L274"),
            Folder("Library/Application Support/Cursor/CachedConfigurations", .cache, source: "https://github.com/microsoft/vscode/blob/0817aaa824590067854c361e77eb973a08b3cf48/src/vs/workbench/services/configuration/common/configurationCache.ts#L66"),
            Folder(
                "Library/Application Support/Cursor/User/workspaceStorage", .projectState, source: "https://github.com/microsoft/vscode/blob/0817aaa824590067854c361e77eb973a08b3cf48/src/vs/platform/storage/electron-main/storageMain.ts#L469-L482",
                rowsDepth: 1, rowsAreProjectState: true
            ),
        ]),
        Definition(id: "windsurf", name: "Windsurf & Devin", systemImage: "curlybraces", appBundleIdentifiers: ["com.exafunction.windsurf", "ai.cognition.devin"], folders: [
            Folder("Library/Application Support/Devin/Cache", .cache, source: "https://github.com/electron/electron/blob/df79406cecfd393f38d5a18b83379d4ba85cc29b/shell/browser/net/network_context_service.cc#L94-L95"),
            Folder("Library/Application Support/Devin/CachedData", .cache, source: "https://github.com/microsoft/vscode/blob/0817aaa824590067854c361e77eb973a08b3cf48/src/mainImpl.ts#L649-L668"),
            Folder("Library/Application Support/Windsurf/Cache", .cache, source: "https://github.com/electron/electron/blob/df79406cecfd393f38d5a18b83379d4ba85cc29b/shell/browser/net/network_context_service.cc#L94-L95"),
            Folder("Library/Application Support/Windsurf/CachedData", .cache, source: "https://github.com/microsoft/vscode/blob/0817aaa824590067854c361e77eb973a08b3cf48/src/mainImpl.ts#L649-L668"),
        ]),
        Definition(id: "nova", name: "Nova", systemImage: "curlybraces", appBundleIdentifiers: ["com.panic.Nova"], folders: [
            Folder("Library/Caches/com.panic.Nova", .cache, source: "https://developer.apple.com/documentation/foundation/filemanager/searchpathdirectory/cachesdirectory"),
        ]),
        Definition(id: "zed", name: "Zed", systemImage: "curlybraces", appBundleIdentifiers: ["dev.zed.Zed"], folders: [
            Folder("Library/Caches/Zed", .cache, source: "https://github.com/zed-industries/zed/blob/a84689073d296dfd39987bc7dd478e43ef76d83a/crates/paths/src/paths.rs#L192-L199"),
            Folder("Library/Logs/Zed", .logs, source: "https://github.com/zed-industries/zed/blob/a84689073d296dfd39987bc7dd478e43ef76d83a/crates/paths/src/paths.rs#L228-L235"),
            Folder("Library/Application Support/Zed/node/node-*/cache", .cache, source: "https://github.com/zed-industries/zed/blob/a84689073d296dfd39987bc7dd478e43ef76d83a/crates/node_runtime/src/node_runtime.rs#L721-L724"),
            Folder("Library/Application Support/Zed/hang_traces", .logs, source: "https://github.com/zed-industries/zed/blob/a84689073d296dfd39987bc7dd478e43ef76d83a/crates/paths/src/paths.rs#L221-L225"),
            Folder("Library/Application Support/Zed/remote_servers", .downloads, source: "https://github.com/zed-industries/zed/blob/a84689073d296dfd39987bc7dd478e43ef76d83a/crates/paths/src/paths.rs#L474-L478"),
            Folder("Library/Application Support/Zed/languages", .environments, source: "https://github.com/zed-industries/zed/blob/a84689073d296dfd39987bc7dd478e43ef76d83a/crates/paths/src/paths.rs#L438-L444"),
            Folder("Library/Application Support/Zed/debug_adapters", .environments, source: "https://github.com/zed-industries/zed/blob/a84689073d296dfd39987bc7dd478e43ef76d83a/crates/paths/src/paths.rs#L446-L452"),
        ]),
        Definition(id: "sublime", name: "Sublime Text", systemImage: "curlybraces", appBundleIdentifiers: ["com.sublimetext.4", "com.sublimetext.3"], folders: [
            Folder("Library/Caches/Sublime Text", .cache, source: "https://www.sublimetext.com/docs/revert.html"),
            Folder("Library/Caches/com.sublimetext.4", .cache, source: "https://developer.apple.com/documentation/foundation/filemanager/searchpathdirectory/cachesdirectory"),
            Folder("Library/Caches/com.sublimetext.3", .cache, source: "https://developer.apple.com/documentation/foundation/filemanager/searchpathdirectory/cachesdirectory"),
        ]),
        Definition(id: "androidstudio", name: "Android Studio", systemImage: "curlybraces", appBundleIdentifiers: withEarlyAccess(["com.google.android.studio"]), folders: [
            Folder("Library/Caches/Google/AndroidStudio*/caches", .cache, source: "https://developer.android.com/studio/troubleshoot"),
            Folder("Library/Caches/Google/AndroidStudio*/index", .cache, source: "https://developer.android.com/studio/troubleshoot"),
            Folder("Library/Caches/Google/AndroidStudio*/tmp", .cache, source: "https://developer.android.com/studio/troubleshoot"),
            Folder("Library/Logs/Google/AndroidStudio*", .logs, source: "https://developer.android.com/studio/troubleshoot"),
            Folder(".android/cache", .downloads, source: "https://android.googlesource.com/platform/tools/base/+/55f19833771c87543085e99f6d2a6d92ea2adddd/sdklib/src/main/java/com/android/sdklib/repository/legacy/remote/internal/DownloadCache.java#219"),
            Folder(".android/build-cache", .buildData, source: "https://android.googlesource.com/platform/tools/base/+/55f19833771c87543085e99f6d2a6d92ea2adddd/build-system/gradle-core/src/main/java/com/android/build/gradle/internal/BuildCacheUtils.java#108"),
        ], ownFolders: ["Library/Caches/Google/AndroidStudio*", "Library/Logs/Google/AndroidStudio*"]),
        Definition(id: "neovim", name: "Neovim", systemImage: "curlybraces", appBundleIdentifiers: [], folders: [
            Folder(".cache/nvim", .cache, source: "https://github.com/neovim/neovim/blob/f76c1ca25a6cba0a0e2cbb916e14995bd7f987b3/runtime/doc/starting.txt#L1404-L1405"),
            Folder(".local/share/nvim/lazy", .environments, source: "https://github.com/folke/lazy.nvim/blob/306a05526ada86a7b30af95c5cc81ffba93fef97/lua/lazy/core/config.lua#L8"),
            Folder(".local/share/nvim/lazy-rocks", .environments, source: "https://github.com/folke/lazy.nvim/blob/306a05526ada86a7b30af95c5cc81ffba93fef97/lua/lazy/core/config.lua#L61"),
            Folder(".local/share/nvim/mason", .environments, source: "https://github.com/mason-org/mason.nvim/blob/2a6940af80375532e5e9e7c1f2fc6319a1b7a69d/lua/mason/settings.lua#L9"),
            Folder(".local/state/nvim/lazy", .cache, source: "https://github.com/folke/lazy.nvim/blob/306a05526ada86a7b30af95c5cc81ffba93fef97/lua/lazy/core/config.lua#L220-L225"),
            Folder(".local/state/nvim/logs", .logs, source: "https://github.com/neovim/neovim/blob/f76c1ca25a6cba0a0e2cbb916e14995bd7f987b3/runtime/doc/starting.txt#L1409-L1410"),
        ]),
        // A running Claude Code session reads its shell snapshot for every command, and the history names what is in
        // `paste-cache`, so neither is listed.
        Definition(id: "claudecode", name: "Claude Code", systemImage: "terminal", appBundleIdentifiers: [], folders: [
            Folder(
                ".local/share/claude/versions", .environments,
                source: "https://code.claude.com/docs/en/setup#auto-updates", launchers: [".local/bin/claude"]
            ),
            Folder(".claude/cache", .cache, source: "https://code.claude.com/docs/en/claude-directory"),
            Folder(".claude/debug", .logs, source: "https://code.claude.com/docs/en/claude-directory"),
            Folder(".claude/statsig", .cache, source: "https://code.claude.com/docs/en/claude-directory"),
        ]),
        Definition(id: "codex", name: "Codex CLI", systemImage: "terminal", appBundleIdentifiers: [], folders: [
            Folder(".codex/log", .logs, source: "https://github.com/openai/codex/blob/dde5f8c5ae9b644c6882b3a48581ac317255d597/codex-rs/core/src/config/mod.rs#L4089-L4093"),
        ]),
        Definition(id: "copilotcli", name: "GitHub Copilot CLI", systemImage: "terminal", appBundleIdentifiers: [], folders: [
            Folder("Library/Caches/copilot", .cache, source: "https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-config-dir-reference"),
            Folder(".copilot/logs", .logs, source: "https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-config-dir-reference"),
        ]),
        Definition(id: "dotslash", name: "DotSlash", systemImage: "arrow.down.circle", appBundleIdentifiers: [], folders: [
            Folder("Library/Caches/dotslash", .downloads, source: "https://github.com/facebook/dotslash/blob/2e9a518ea2564e59312a2d225f55f8701542ee1d/src/dotslash_cache.rs#L76-L85"),
        ]),
        Definition(id: "cursoragent", name: "Cursor CLI", systemImage: "terminal", appBundleIdentifiers: [], folders: [
            Folder(
                ".local/share/cursor-agent/versions", .environments,
                source: "https://cursor.com/install", launchers: [".local/bin/agent", ".local/bin/cursor-agent"]
            ),
        ]),
        Definition(id: "opencode", name: "opencode", systemImage: "terminal", appBundleIdentifiers: [], folders: [
            Folder(".cache/opencode", .cache, source: "https://github.com/anomalyco/opencode/blob/907b3bc518fa48e90e8ec24dd327d13eee71c36c/packages/core/src/global.ts#L12"),
        ]),
        // Cloud tools
        Definition(id: "gcloud", name: "Google Cloud CLI", systemImage: "cloud", appBundleIdentifiers: [], folders: [
            Folder(".config/gcloud/logs", .logs, source: "https://docs.cloud.google.com/compute/docs/troubleshooting/general-tips"),
        ]),
        Definition(id: "azure", name: "Azure CLI", systemImage: "cloud", appBundleIdentifiers: [], folders: [
            Folder(".azure/logs", .logs, source: "https://github.com/microsoft/knack/blob/52f769a135a2c18326e025f510c031c99dfc5f69/knack/log.py#L182-L184"),
            Folder(".azure/telemetry", .cache, source: "https://github.com/Azure/azure-cli/blob/da4c0548a2725ea3d08b1d94b8e7fa1b0b07256e/src/azure-cli-telemetry/azure/cli/telemetry/util.py#L30"),
            Folder(".azure/commands", .logs, source: "https://github.com/Azure/azure-cli/blob/da4c0548a2725ea3d08b1d94b8e7fa1b0b07256e/src/azure-cli-core/azure/cli/core/azlogging.py#L61"),
        ]),
        Definition(id: "kubectl", name: "kubectl", systemImage: "cloud", appBundleIdentifiers: [], folders: [
            Folder(".kube/cache/discovery", .cache, source: "https://github.com/kubernetes/cli-runtime/blob/16d14b1ae2188112e291bb04cdf46f34bc8c021d/pkg/genericclioptions/config_flags.go#L317-L331"),
            Folder(".kube/cache/http", .cache, source: "https://github.com/kubernetes/cli-runtime/blob/16d14b1ae2188112e291bb04cdf46f34bc8c021d/pkg/genericclioptions/config_flags.go#L317"),
        ]),
        Definition(id: "helm", name: "Helm", systemImage: "cloud", appBundleIdentifiers: [], folders: [
            Folder("Library/Caches/helm", .cache, source: "https://github.com/helm/helm/blob/53dfa521e019f7b832497066032406b9cda9d5d4/pkg/helmpath/lazypath_darwin.go#L32-L34"),
        ]),
        Definition(id: "githubcli", name: "GitHub CLI", systemImage: "cloud", appBundleIdentifiers: [], folders: [
            Folder(".cache/gh", .cache, source: "https://github.com/cli/go-gh/blob/68c032df142b15f041b7b53d5fcae8a918140e69/pkg/config/config.go#L299-L306"),
        ]),
        Definition(id: "terraform", name: "Terraform", systemImage: "cloud", appBundleIdentifiers: [], folders: [
            Folder(".terraform.d/plugin-cache", .environments, source: "https://developer.hashicorp.com/terraform/cli/config/config-file"),
        ]),
        Definition(id: "pulumi", name: "Pulumi", systemImage: "cloud", appBundleIdentifiers: [], folders: [
            Folder(".pulumi/plugins", .downloads, source: "https://github.com/pulumi/docs/blob/0ea308cd7a6c2b6ee675b855ea2faccb2c43fe84/content/docs/iac/concepts/plugins.md#L83"),
        ]),
        Definition(id: "vercel", name: "Vercel CLI", systemImage: "cloud", appBundleIdentifiers: [], folders: [
            Folder("Library/Caches/com.vercel.cli", .cache, source: "https://github.com/vercel/vercel/blob/c628be7835e03a965b93e9cf9e2bd5ac2acbf5eb/packages/cli-config/src/paths.ts#L33-L35"),
        ]),
        // Netlify keeps its token in `config.json` in the same folder, so only these two subfolders are listed.
        Definition(id: "netlify", name: "Netlify CLI", systemImage: "cloud", appBundleIdentifiers: [], folders: [
            Folder("Library/Preferences/netlify/deno-cli", .downloads, source: "https://github.com/netlify/build/blob/03ae88564579d2addfc82970d0b8583963f886aa/packages/edge-bundler/node/bridge.ts#L66"),
            Folder("Library/Preferences/netlify/tunnel", .downloads, source: "https://github.com/netlify/cli/blob/7f1c866914f261e8d57c85763487db88bfb61440/src/utils/live-tunnel.ts#L86"),
        ]),
        Definition(id: "firebase", name: "Firebase CLI", systemImage: "cloud", appBundleIdentifiers: [], folders: [
            Folder(".cache/firebase", .downloads, source: "https://github.com/firebase/firebase-tools/blob/7f7747228cc583ecdaf053ac44f238bffc77f6f0/src/emulator/downloadableEmulators.ts#L29-L30"),
        ]),
        // Virtual machines
        // Docker Desktop's own logs. Its disk image, `Data/vms`, is Space's to show and never offered here.
        Definition(
            id: "docker", name: "Docker Desktop", systemImage: "server.rack", appBundleIdentifiers: ["com.docker.docker"],
            folders: [
                Folder("Library/Containers/com.docker.docker/Data/log", .logs, source: "https://github.com/docker/docs/blob/1cb9a4d2c65d712da863e30cd3a1319ddeea3298/content/manuals/engine/daemon/logs.md#L16"),
            ]
        ),
        Definition(id: "lima", name: "Lima", systemImage: "server.rack", appBundleIdentifiers: [], folders: [
            Folder("Library/Caches/lima", .downloads, source: "https://github.com/lima-vm/lima/blob/97b6b86ca429d836830e62394b1dd91acbef8e5f/website/content/en/docs/dev/internals.md#L137-L145"),
        ]),
        Definition(id: "tart", name: "Tart", systemImage: "server.rack", appBundleIdentifiers: [], folders: [
            Folder(".tart/cache", .downloads, source: "https://github.com/cirruslabs/tart/blob/05edeac562bae804ea4f88592cfbc98cc6791b5d/Sources/tart/Config.swift#L21"),
        ]),
        Definition(id: "colima", name: "Colima", systemImage: "server.rack", appBundleIdentifiers: [], folders: [
            Folder("Library/Caches/colima", .downloads, source: "https://github.com/abiosoft/colima/blob/49dfe87aecc1645905d0fb8a0e43ce29e12138f6/cmd/prune.go#L25-L41"),
        ]),
        Definition(id: "minikube", name: "minikube", systemImage: "server.rack", appBundleIdentifiers: [], folders: [
            Folder(".minikube/cache/iso", .downloads, source: "https://github.com/kubernetes/minikube/blob/39ac29da339bbb70b778a9b606c5bcdb97c1fb7b/site/content/en/docs/handbook/offline.md#L10-L17"),
            Folder(".minikube/cache/kic", .downloads, source: "https://github.com/kubernetes/minikube/blob/39ac29da339bbb70b778a9b606c5bcdb97c1fb7b/site/content/en/docs/handbook/offline.md#L10-L17"),
            Folder(".minikube/cache/preloaded-tarball", .downloads, source: "https://github.com/kubernetes/minikube/blob/39ac29da339bbb70b778a9b606c5bcdb97c1fb7b/site/content/en/docs/handbook/offline.md#L10-L17"),
            Folder(".minikube/cache/linux", .downloads, source: "https://github.com/kubernetes/minikube/blob/39ac29da339bbb70b778a9b606c5bcdb97c1fb7b/site/content/en/docs/handbook/offline.md#L10-L17"),
            Folder(".minikube/cache/darwin", .downloads, source: "https://github.com/kubernetes/minikube/blob/39ac29da339bbb70b778a9b606c5bcdb97c1fb7b/pkg/minikube/node/cache.go#L113-L121"),
        ]),
        Definition(id: "vagrant", name: "Vagrant", systemImage: "server.rack", appBundleIdentifiers: [], folders: [
            Folder(".vagrant.d/boxes", .keptDownloads, source: "https://github.com/hashicorp/vagrant/blob/dc55920a284544919340b975098b4ac9005b08b0/lib/vagrant/environment.rb#L140"),
            Folder(".vagrant.d/tmp", .cache, source: "https://github.com/hashicorp/vagrant/blob/dc55920a284544919340b975098b4ac9005b08b0/lib/vagrant/environment.rb#L143"),
        ]),
        // The modules Clang compiles for `@import` and `-fmodules`, kept in `cache_directory()/clang/ModuleCache`.
        Definition(id: "clang", name: "Clang", systemImage: "hammer", appBundleIdentifiers: [], folders: [
            Folder(
                "clang/ModuleCache", .cache,
                source: "https://github.com/llvm/llvm-project/blob/3ff9208af10d7a6e246e0e411ecfd8db7993baba/clang/lib/Driver/ToolChains/Clang.cpp#L4045-L4057",
                base: .userCache
            ),
        ]),
        // Build systems and media
        // Only the scanner's cache: `ssl` beside it holds the client certificates the scanner signs in with.
        Definition(id: "sonar", name: "SonarScanner", systemImage: "hammer", appBundleIdentifiers: [], folders: [
            Folder(".sonar/cache", .downloads, source: "https://github.com/SonarSource/sonar-scanner-java-library/blob/acfe1ac2b7e0653332112d4bba2e9ba7586f91ba/lib/src/main/java/org/sonarsource/scanner/lib/ScannerEngineBootstrapper.java#L137"),
        ]),
        Definition(id: "ccache", name: "ccache", systemImage: "gearshape.2", appBundleIdentifiers: [], folders: [
            Folder("Library/Caches/ccache", .buildData, source: "https://github.com/ccache/ccache/blob/052c47fb85324363a05ddfc51b79fba7d6951ea7/doc/manual.adoc#L575-L577"),
            // A legacy `~/.ccache` also holds `ccache.conf` (https://ccache.dev/manual/latest.html), so only
            // the cache's own shards and its temporary folder are named.
            Folder(".ccache/[0-9a-f]", .buildData, source: "https://github.com/ccache/ccache/blob/052c47fb85324363a05ddfc51b79fba7d6951ea7/doc/manual.adoc#L375-L376"),
            Folder(".ccache/tmp", .buildData, source: "https://github.com/ccache/ccache/blob/052c47fb85324363a05ddfc51b79fba7d6951ea7/doc/manual.adoc#L1246-L1252"),
        ]),
        Definition(id: "bazel", name: "Bazel", systemImage: "gearshape.2", appBundleIdentifiers: [], folders: [
            Folder("Library/Caches/bazel", .buildData, source: "https://github.com/bazelbuild/bazel/blob/9e19427a2a5e782d4a106f9b1a4b7b92651b0e18/docs/remote/output-directories.mdx#L32-L41"),
            Folder("Library/Caches/bazelisk", .downloads, source: "https://github.com/bazelbuild/bazelisk/blob/e59b730a8380af9c313afeca366e0191f8141eae/README.md#L312"),
        ]),
        Definition(id: "zig", name: "Zig", systemImage: "gearshape.2", appBundleIdentifiers: [], folders: [
            Folder(".cache/zig", .buildData, source: "https://codeberg.org/ziglang/zig/src/branch/master/lib/std/zig.zig#L1586-L1610"),
        ]),
        Definition(id: "vcpkg", name: "vcpkg", systemImage: "gearshape.2", appBundleIdentifiers: [], folders: [
            Folder(".cache/vcpkg/archives", .buildData, source: "https://github.com/microsoft/vcpkg-tool/blob/4bbb0f73b293c2701541c640a6a4f8cbbf31018e/src/vcpkg/binarycaching.cpp#L1742-L1746"),
        ]),
        Definition(id: "conan", name: "Conan", systemImage: "gearshape.2", appBundleIdentifiers: [], folders: [
            Folder(".conan2/p", .environments, source: "https://github.com/conan-io/conan/blob/342f0391c096133f5775a9d7cf48a0e6f31ffd35/conan/internal/cache/cache.py#L27-L28"),
        ]),
        Definition(id: "pants", name: "Pants", systemImage: "gearshape.2", appBundleIdentifiers: [], folders: [
            Folder(".cache/pants/lmdb_store", .buildData, source: "https://github.com/pantsbuild/pants/blob/e20cd55c4cdbdc93ce67a62c3a08d670138f78d8/docs/docs/using-pants/troubleshooting-common-issues.mdx#L159"),
            Folder(".cache/pants/named_caches", .downloads, source: "https://github.com/pantsbuild/pants/blob/e20cd55c4cdbdc93ce67a62c3a08d670138f78d8/docs/docs/using-pants/troubleshooting-common-issues.mdx#L160"),
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
            Folder("Library/Caches/Godot", .cache, source: "https://github.com/godotengine/godot-docs/blob/a52125d6d0e9eee1fe5e83fea4e496fec313ddf9/tutorials/io/data_paths.rst#L157-L166"),
            Folder("Library/Application Support/Godot/export_templates", .keptDownloads, source: "https://github.com/godotengine/godot/blob/e7cfa294a0b81bed7986be04a848cc1832a3f083/editor/file_system/editor_paths.h#L47"),
        ]),
        Definition(id: "blender", name: "Blender", systemImage: "cube.transparent", appBundleIdentifiers: ["org.blenderfoundation.blender"], folders: [
            Folder("Library/Caches/Blender", .cache, source: "https://projects.blender.org/blender/blender/src/commit/703834468bfa0464da39634f3cf346a078d5236c/source/blender/blenkernel/intern/appdir.cc#L228"),
        ]),
        Definition(id: "adobe", name: "Adobe Media Cache", systemImage: "play.rectangle", appBundleIdentifiers: [], folders: [
            Folder("Library/Application Support/Adobe/Common/Media Cache Files", .cache, source: "https://helpx.adobe.com/premiere/desktop/troubleshooting/media-issues/delete-media-cache-files-manually.html"),
            Folder("Library/Application Support/Adobe/Common/Media Cache", .cache, source: "https://helpx.adobe.com/premiere/desktop/troubleshooting/media-issues/delete-media-cache-files-manually.html"),
        ]),
        // Quantum computing. Everything else these SDKs write in the home folder is settings or an account
        // token, so only these three folders are listed.
        Definition(id: "dwave", name: "D-Wave Ocean", systemImage: "atom", appBundleIdentifiers: [], folders: [
            Folder("Library/Caches/dwave-cloud-client", .cache, source: "https://github.com/dwavesystems/dwave-cloud-client/blob/224246a6438fad15ee598423c8abfb39f2cb37c9/dwave/cloud/config/loaders.py#L283-L289"),
        ]),
        Definition(id: "qutip", name: "QuTiP", systemImage: "atom", appBundleIdentifiers: [], folders: [
            Folder(".qutip/qutip_coeffs_*", .buildData, source: "https://github.com/qutip/qutip/blob/56ed7854177e046124118fdcb6b958d557b65984/qutip/settings.py#L278-L283"),
        ]),
        Definition(id: "qbraid", name: "qBraid", systemImage: "atom", appBundleIdentifiers: [], folders: [
            Folder(".qbraid/environments", .environments, source: "https://docs.qbraid.com/cli/user-guide/environments"),
        ]),

        // Models and datasets
        Definition(id: "ollama", name: "Ollama", systemImage: "brain", appBundleIdentifiers: ["com.electron.ollama"], folders: [
            Folder(".ollama/models", .models, source: "https://github.com/ollama/ollama/blob/42e911bc3d05798cad729cb474bf62f378cb2e26/docs/faq.mdx#L233-L236"),
            Folder(".ollama/logs", .logs, source: "https://github.com/ollama/ollama/blob/42e911bc3d05798cad729cb474bf62f378cb2e26/docs/macos.mdx#L26-L28"),
            Folder("Library/Caches/ollama/updates", .downloads, source: "https://github.com/ollama/ollama/blob/42e911bc3d05798cad729cb474bf62f378cb2e26/app/updater/updater_darwin.go#L88-L96"),
        ]),
        Definition(id: "lmstudio", name: "LM Studio", systemImage: "brain", appBundleIdentifiers: [], folders: [
            Folder(".lmstudio/models", .models, source: "https://lmstudio.ai/docs/app/advanced/import-model"),
            Folder(".cache/lm-studio/models", .models, source: "https://lmstudio.ai/blog/lmstudio-v0.3.6"),
        ]),
        Definition(id: "huggingface", name: "Hugging Face", systemImage: "brain", appBundleIdentifiers: [], folders: [
            Folder(".cache/huggingface/hub", .models, source: "https://github.com/huggingface/huggingface_hub/blob/d711944ddf94abe9ef2a34f80d41007968ff9c30/docs/source/en/package_reference/environment_variables.md#L37-L42"),
            Folder(".cache/huggingface/datasets", .models, source: "https://github.com/huggingface/datasets/blob/af4347bd438a00e7c688661f7ae1e377674e0a97/docs/source/cache.mdx#L20"),
            Folder(".cache/huggingface/xet", .cache, source: "https://github.com/huggingface/huggingface_hub/blob/d711944ddf94abe9ef2a34f80d41007968ff9c30/docs/source/en/package_reference/environment_variables.md#L44-L48"),
            Folder(".cache/huggingface/assets", .cache, source: "https://github.com/huggingface/huggingface_hub/blob/d711944ddf94abe9ef2a34f80d41007968ff9c30/docs/source/en/package_reference/environment_variables.md#L50-L56"),
            Folder(".cache/huggingface/transformers", .models, source: "https://github.com/huggingface/transformers/blob/983e40ac3b2af68fd6c927dce09324d54d023e54/src/transformers/utils/hub.py#L70"),
            Folder(".cache/huggingface/modules", .cache, source: "https://github.com/huggingface/transformers/blob/469230357aab0f2b303b0d638c1f8d06edb14184/src/transformers/utils/hub.py#L108"),
        ]),
        Definition(id: "torch", name: "PyTorch", systemImage: "brain", appBundleIdentifiers: [], folders: [
            Folder(".cache/torch/hub", .models, source: "https://github.com/pytorch/pytorch/blob/e8f41c0ef97e73484550856d369c702f69fc10e1/docs/source/hub.md#L122-L124"),
            Folder(".cache/torch/transformers", .models, source: "https://github.com/huggingface/transformers/blob/983e40ac3b2af68fd6c927dce09324d54d023e54/src/transformers/utils/hub.py#L65"),
        ]),
        Definition(id: "mlxdata", name: "MLX Data", systemImage: "brain", appBundleIdentifiers: [], folders: [
            Folder(".cache/mlx.data", .models, source: "https://github.com/ml-explore/mlx-data/blob/2f431e90a06c33d2e3f78019b32c563e8fd8a71a/python/mlx/data/datasets/common.py#L11"),
        ]),
        Definition(id: "whisper", name: "Whisper", systemImage: "brain", appBundleIdentifiers: [], folders: [
            Folder(".cache/whisper", .models, source: "https://github.com/openai/whisper/blob/86098128c0b4f24f0e2aa2994de830614b474227/whisper/__init__.py#L119-L134"),
        ]),
        Definition(id: "gpt4all", name: "GPT4All", systemImage: "brain", appBundleIdentifiers: [], folders: [
            Folder(".cache/gpt4all", .models, source: "https://github.com/nomic-ai/gpt4all/blob/b666d16db5aeab8b91aaf7963adcee9c643734d7/gpt4all-bindings/python/gpt4all/gpt4all.py#L36"),
        ]),
        Definition(id: "tensorflow", name: "TensorFlow Datasets", systemImage: "brain", appBundleIdentifiers: [], folders: [
            Folder("tensorflow_datasets", .models, source: "https://github.com/tensorflow/datasets/blob/ff9ea5fdcba7cc4d25bac833ecb6659397694c12/tensorflow_datasets/core/constants.py#L36-L37"),
        ]),
        Definition(id: "keras", name: "Keras", systemImage: "brain", appBundleIdentifiers: [], folders: [
            Folder(".keras/datasets", .models, source: "https://github.com/keras-team/keras/blob/f7116e50cde59245a7b56871b337ca03eb703d11/keras/src/utils/file_utils.py#L230-L232"),
            Folder(".keras/models", .models, source: "https://github.com/keras-team/keras/blob/f7116e50cde59245a7b56871b337ca03eb703d11/keras/src/applications/resnet.py#L209"),
        ]),
        Definition(id: "nltk", name: "NLTK Data", systemImage: "brain", appBundleIdentifiers: [], folders: [
            Folder("nltk_data", .models, source: "https://github.com/nltk/nltk/blob/350c1c70948fda15ba8db1bea973513d33b2c187/nltk/downloader.py#L1737-L1743"),
        ]),
        Definition(id: "llamacpp", name: "llama.cpp", systemImage: "brain", appBundleIdentifiers: [], folders: [
            Folder("Library/Caches/llama.cpp", .models, source: "https://github.com/ggml-org/llama.cpp/blob/11fe02151f79c41d0d4af7da708755d73b9c0da6/common/common.cpp#L988-L1007"),
        ]),
        Definition(id: "modelscope", name: "ModelScope", systemImage: "brain", appBundleIdentifiers: [], folders: [
            Folder(".cache/modelscope/hub", .models, source: "https://github.com/modelscope/modelscope/blob/6cb35d56b5e45cf30154d85b56db3c67edb032ac/modelscope/utils/file_utils.py#L41-L46"),
        ]),
        Definition(id: "kagglehub", name: "Kaggle Hub", systemImage: "brain", appBundleIdentifiers: [], folders: [
            Folder(".cache/kagglehub", .models, source: "https://github.com/Kaggle/kagglehub/blob/4fe0a176e0e9b815ca4101c371b504ff97239b97/src/kagglehub/config.py#L17"),
        ]),
        Definition(id: "jan", name: "Jan", systemImage: "brain", appBundleIdentifiers: ["jan.ai.app"], folders: [
            Folder("Library/Application Support/Jan/data/llamacpp/models", .models, source: "https://jan.ai/docs/desktop/data-folder"),
            Folder("Library/Application Support/Jan/data/mlx/models", .models, source: "https://jan.ai/docs/desktop/data-folder"),
            Folder("Library/Application Support/Jan/data/logs", .logs, source: "https://jan.ai/docs/desktop/data-folder"),
        ]),
        // Chromium's docs/user_data_dir.md names each Chrome channel's and Chromium's folder, Brave's own importer
        // names Brave's, and Opera's desktop blog names Opera's (blogs.opera.com/desktop/2023/08). Their disk caches
        // are in `Library/Caches`, which Space empties.
        Definition(
            id: "chrome", name: "Google Chrome", systemImage: "globe",
            appBundleIdentifiers: ["com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.dev",
                                   "com.google.Chrome.canary"],
            folders: ["Chrome", "Chrome Beta", "Chrome Dev", "Chrome Canary"].flatMap {
                chromiumFolders(in: "Library/Application Support/Google/\($0)")
            }
        ),
        // Google's updater, which keeps Chrome and Google's other apps up to date, keeps the last update it downloaded
        // for each app, and only that one (Chromium's `components/update_client/crx_cache.h`), in `crx_cache` inside
        // its own folder, `Application Support/<company>/<product>` (`chrome/updater/util/mac_path_util.mm`).
        Definition(
            id: "googleupdater", name: "Google Updater", systemImage: "shippingbox",
            appBundleIdentifiers: ["com.google.GoogleUpdater"],
            folders: [
                Folder("Library/Application Support/Google/GoogleUpdater/crx_cache", .downloads, source: "https://github.com/chromium/chromium/blob/54cc36437b23cee8aaffa1289c8bc31bf2f520b9/chrome/updater/util/util.cc#L112-L115"),
            ]
        ),
        Definition(
            id: "chromium", name: "Chromium", systemImage: "globe", appBundleIdentifiers: ["org.chromium.Chromium"],
            folders: chromiumFolders(in: "Library/Application Support/Chromium")
        ),
        Definition(
            id: "brave", name: "Brave", systemImage: "globe", appBundleIdentifiers: ["com.brave.Browser"],
            folders: chromiumFolders(in: "Library/Application Support/BraveSoftware/Brave-Browser")
        ),
        Definition(
            id: "opera", name: "Opera", systemImage: "globe", appBundleIdentifiers: ["com.operasoftware.Opera"],
            folders: chromiumFolders(in: "Library/Application Support/com.operasoftware.Opera")
        ),
        // chrome-devtools-mcp drives Chrome in a user data folder of its own, one per channel, for its server and its
        // command line alike (src/browser.ts at commit 9a47b657d7b17b9bc64508530c93d55e8033e2a6 of
        // github.com/ChromeDevTools/chrome-devtools-mcp), so it waits for Chrome to quit.
        Definition(
            id: "chrome-devtools-mcp", name: "Chrome DevTools MCP", systemImage: "globe",
            appBundleIdentifiers: ["com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.dev",
                                   "com.google.Chrome.canary"],
            folders: ["chrome-devtools-mcp", "chrome-devtools-mcp-cli"].flatMap { tool in
                ["", "-canary", "-beta", "-dev"].flatMap { chromiumFolders(in: ".cache/\(tool)/chrome-profile\($0)") }
            }
        ),
    ]

    /// The identifiers of apps built on IntelliJ, each also as its early access build, whose identifier IntelliJ's
    /// build ends in `-EAP` (`platform/build-scripts/resources/mac/Contents/Info.plist`).
    private static func withEarlyAccess(_ identifiers: [String]) -> [String] {
        identifiers + identifiers.map { $0 + "-EAP" }
    }

    /// The caches and models Chromium keeps in a browser's user data folder, beside its profiles and in each of them,
    /// named where Chromium names them. What a profile holds for the person, its site data included, is never listed.
    private static func chromiumFolders(in userData: String) -> [Folder] {
        let browser = "https://github.com/chromium/chromium/blob/54cc36437b23cee8aaffa1289c8bc31bf2f520b9/chrome/browser/"
        let gpu = "https://github.com/chromium/chromium/blob/54cc36437b23cee8aaffa1289c8bc31bf2f520b9/gpu/ipc/common/gpu_disk_cache_type.cc#L43-L50"
        return ["ShaderCache", "GrShaderCache", "GraphiteDawnCache", "GPUPersistentCache"].map {
            Folder("\(userData)/\($0)", .cache, source: browser + "chrome_content_browser_client.cc#L5199-L5224")
        } + [
            Folder(
                "\(userData)/component_crx_cache", .downloads,
                source: browser + "component_updater/chrome_component_updater_configurator.cc#L135-L140"
            ),
            Folder(
                "\(userData)/extensions_crx_cache", .downloads,
                source: browser + "extensions/updater/chrome_update_client_config.cc#L192-L197"
            ),
        ] + ["GPUCache", "DawnWebGPUCache", "DawnGraphiteCache"].map {
            Folder("\(userData)/*/\($0)", .cache, source: gpu)
        } + chromiumModels(in: userData)
    }

    /// The on-device models the component updater installs again when a feature asks for one, and the models the
    /// optimization guide downloads. Components go in the user data folder:
    /// `chrome_main_delegate.cc` registers the component updater's folder under `DIR_USER_DATA`.
    private static func chromiumModels(in userData: String) -> [Folder] {
        let installer = "https://github.com/chromium/chromium/blob/54cc36437b23cee8aaffa1289c8bc31bf2f520b9/chrome/browser/component_updater/"
            + "optimization_guide_on_device_model_installer.cc"
        let store = "https://github.com/chromium/chromium/blob/54cc36437b23cee8aaffa1289c8bc31bf2f520b9/chrome/browser/optimization_guide/model_execution/"
            + "optimization_guide_global_state.cc#L101-L107"
        return [
            Folder("\(userData)/OptGuideOnDeviceModel", .models, source: installer + "#L73-L76"),
            Folder("\(userData)/OptGuideManifestModel", .models, source: installer + "#L84-L85"),
            Folder("\(userData)/optimization_guide_model_store", .models, source: store),
        ]
    }

    @concurrent
    public static func scan(
        in environment: SearchEnvironment = .current, exclusions: Exclusions = .none
    ) async -> [DeveloperEnvironment] {
        let apps = await AppCatalog.installedApps(in: AppCatalog.directories(in: environment))
        let electron = electronDefinitions(for: apps, home: environment.homeDirectory)
        return await scan(
            definitions + electron, homeDirectory: environment.homeDirectory,
            userCacheDirectory: environment.userCacheDirectory,
            userTemporaryDirectory: environment.userTemporaryDirectory, exclusions: exclusions
        )
    }

    /// One definition for each installed Electron app whose session data folder, `Application Support/<its name>` as
    /// Electron's `docs/api/app.md` puts it, holds the `Local State` Electron writes there. It lists only what Electron
    /// and Chromium name as caches, and an app a definition of the table already covers is left to that definition.
    static func electronDefinitions(for apps: [InstalledApp], home: URL) -> [Definition] {
        let covered = Set(definitions.flatMap(\.folders).compactMap { folder -> String? in
            let names = PathComponents.of(folder.path)
            guard names.count > 2, names[0] == "Library", names[1] == "Application Support" else { return nil }
            return names[2].lowercased()
        })
        let electron = "https://github.com/electron/electron/blob/df79406cecfd393f38d5a18b83379d4ba85cc29b/shell/browser/"
        let chromium = "https://github.com/chromium/chromium/blob/54cc36437b23cee8aaffa1289c8bc31bf2f520b9/"
        let codeCache = chromium + "content/browser/storage_partition_impl.cc#L1587-L1595"
        let exists = { (url: URL) in FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) }
        return apps.compactMap { app in
            guard let identifier = app.bundleIdentifier, let name = app.bundleName, !name.isEmpty, !name.contains("/"),
                  !covered.contains(name.lowercased()),
                  exists(app.url.appending(path: "Contents/Frameworks/Electron Framework.framework"))
            else { return nil }
            let data = "Library/Application Support/\(name)"
            guard exists(home.appending(path: "\(data)/Local State")) else { return nil }
            // Each persistent session an app opens keeps the same caches in a folder of its own.
            let partitions = "\(data)/Partitions/*"
            let partition = electron + "electron_browser_context.cc#L384-L390"
            let folders = [
                Folder("\(data)/Cache", .cache, source: electron + "net/network_context_service.cc#L94-L95"),
                Folder("\(data)/Code Cache", .cache, source: codeCache),
                Folder("\(partitions)/Cache", .cache, source: partition),
                Folder("\(partitions)/Code Cache", .cache, source: partition),
            ] + ["GPUCache", "DawnWebGPUCache", "DawnGraphiteCache"].flatMap { cache in
                [
                    Folder("\(data)/\(cache)", .cache, source: chromium + "gpu/ipc/common/gpu_disk_cache_type.cc#L43-L50"),
                    Folder("\(partitions)/\(cache)", .cache, source: partition),
                ]
            } + ["ShaderCache", "GrShaderCache", "GraphiteDawnCache", "GPUPersistentCache"].map {
                Folder("\(data)/\($0)", .cache, source: electron + "electron_browser_client.cc#L1206-L1222")
            }
            return Definition(
                id: "electron.\(identifier)", name: app.name, systemImage: "macwindow",
                appBundleIdentifiers: [identifier], folders: folders
            )
        }
    }

    static func scan(
        _ definitions: [Definition],
        homeDirectory: URL,
        userCacheDirectory: URL? = nil,
        userTemporaryDirectory: URL? = nil,
        exclusions: Exclusions = .none,
        measure: @escaping LeftoverScanner.Measure = LeftoverScanner.walk,
        preference: @escaping @Sendable (String) -> String? = Self.xcodePreference,
        openFiles: OpenFiles = OpenFiles()
    ) async -> [DeveloperEnvironment] {
        let settings = ToolSettings(home: homeDirectory)
        // Four tools at a time: measured all at once, their big folders would share the disk and each run out of
        // the time `FileSize` gives a walk, where alone they would finish.
        return await definitions.concurrentMap(width: 4) { definition in
            await environment(
                for: definition, homeDirectory: homeDirectory, userCacheDirectory: userCacheDirectory,
                userTemporaryDirectory: userTemporaryDirectory, exclusions: exclusions, measure: measure,
                preference: preference, settings: settings, openFiles: openFiles
            )
        }
        .compactMap(\.self)
        .sorted { $0.total != $1.total ? $0.total > $1.total : $0.name < $1.name }
    }

    private static func environment(
        for definition: Definition,
        homeDirectory: URL,
        userCacheDirectory: URL?,
        userTemporaryDirectory: URL?,
        exclusions: Exclusions,
        measure: @escaping LeftoverScanner.Measure,
        preference: @escaping @Sendable (String) -> String?,
        settings: ToolSettings,
        openFiles: OpenFiles
    ) async -> DeveloperEnvironment? {
        var found: [(url: URL, folder: Folder, project: String?)] = []
        for folder in definition.folders {
            let places = folder.places(
                home: homeDirectory, userCache: userCacheDirectory, userTemporary: userTemporaryDirectory,
                preference: preference, settings: settings
            )
            let rows = places.flatMap { place in
                folder.launchers.isEmpty
                    ? folder.rows(in: place) : folder.olderVersions(in: place, home: homeDirectory)
            }
            for url in rows {
                guard !exclusions.excludes(url), !exclusions.holds(url) else { continue }
                let project = folder.rowsAreProjectState ? Self.goneProject(at: url) : nil
                guard !folder.rowsAreProjectState || project != nil else { continue }
                // Skips a folder that holds work kept nowhere else, such as the state Deno's
                // scripts keep in `location_data`. Removing it would lose that work.
                guard !ProtectedData.holdsWorkKeptInACache(url.path(percentEncoded: false)) else { continue }
                // Skips a symbolic link, which is how people move a big cache to another disk.
                // Moving the link frees nothing.
                guard (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else { continue }
                guard folder.base != .userTemporary || openFiles.holders(of: url).isEmpty else { continue }
                found.append((url, folder, project))
            }
        }
        // A pattern can reach inside a folder another pattern lists, as `*/GPUCache` reaches
        // `GPUPersistentCache/GPUCache`, and that folder goes with the one around it.
        let paths = found.map { PathPattern.comparablePath(of: $0.url) }
        var locations: [DeveloperEnvironment.Location] = []
        for (url, folder, project) in found {
            guard !Task.isCancelled else { return nil }
            let path = PathPattern.comparablePath(of: url)
            guard !paths.contains(where: { PathComponents.isPath(path, inside: $0) }) else { continue }
            // Awaited, never blocked on: a blocked wait would hold one of the few threads that every scan in the
            // app shares.
            let contents = await measure(url)
            let derived = folder.rowsAreDerivedData ? Self.derivedDataRow(at: url) : nil
            locations.append(DeveloperEnvironment.Location(
                url: url,
                kind: folder.kind(at: url),
                size: contents.flatMap { $0.couldNotBeRead ? nil : $0.size },
                source: folder.source,
                couldNotBeRead: contents?.couldNotBeRead == true,
                archive: folder.kind == .archives ? Self.archive(at: url) : nil,
                workspace: derived?.workspace,
                project: project,
                isTheTools: derived?.isXcodes ?? folder.isTheTools(at: url),
                lastWritten: contents.flatMap { $0.couldNotBeRead ? nil : $0.newestChange },
                heldBack: contents.flatMap(HoldBack.secret(in:))
            ))
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
