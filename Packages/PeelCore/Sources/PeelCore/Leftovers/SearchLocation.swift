import Darwin
public import Foundation
internal import PeelPrivileged

public struct SearchLocation: Sendable, Hashable {
    public enum Kind: String, Sendable, Hashable, CaseIterable {
        case applicationSupport
        case applicationScripts
        case caches
        case containers
        case groupContainers
        case preferences
        case preferencesByHost
        case savedApplicationState
        case recentDocuments
        case logs
        case httpStorages
        case webKit
        case cookies
        case launchAgents
        case launchDaemons
        case privilegedHelperTools
        /// `/Library/StartupItems`, where older software keeps a folder that runs at startup.
        case startupItems
        /// The folders macOS loads plug-ins from.
        case plugIns
        /// `~/Library/Frameworks`, where an app can install a framework other programs load.
        case frameworks
        /// The two files that are an installer receipt, which is how macOS still counts a package as installed.
        case receipts
        /// The top of a Library itself, where a vendor keeps a folder of its own beside macOS's.
        case library
        case temporaryItems
        /// `/Users/Shared`, where apps meant for everyone on the Mac keep their files.
        case sharedFolder
        /// What an app hides in the home folder itself, like `~/.hammerspoon` or `~/.config/op`.
        case hiddenHomeFiles
        /// The top of the home folder, where a few apps keep a folder of their own beside the ones every
        /// account starts with: `~/Postman`, `~/VirtualBox VMs`.
        case homeFolder
        /// `/usr/local/bin` and `/usr/local/sbin`, where an app links the command line tools it carries. Only a
        /// link into the app counts as the app's: a tool is named for what it does (`docker`), not for its maker.
        case commandLineTools
        /// The folders where a browser looks for the manifests of the programs its extensions may run. A manifest
        /// is named for its host, not for the app, so only one whose program is inside the app counts as the app's.
        case nativeMessagingHosts
        /// The folder inside Safari's own `com.apple.Safari.WebApp` container where it keeps a container for each of
        /// its web apps, named by that web app's identifier. Looked into only when a Safari web app is removed.
        case safariWebApps
        /// Somewhere no scan looks, which only a Homebrew cask can name: `~/Documents/Foo`, `/usr/local/etc/foo`.
        case elsewhere
    }

    public let kind: Kind
    public let url: URL
    /// At the top of a Library, the names that same Library searches as places of their own, which it never offers
    /// whole: `Preferences` is looked inside and never moved.
    let skipped: Set<String>

    public init(kind: Kind, url: URL) {
        self.init(kind: kind, url: url, skipped: [])
    }

    init(kind: Kind, url: URL, skipped: Set<String>) {
        self.kind = kind
        self.url = url
        self.skipped = skipped
    }

    /// True when this location looks at an entry with this name.
    func considers(fileName: String) -> Bool {
        kind.considers(fileName: fileName) && !skipped.contains(fileName)
    }
}

extension SearchLocation.Kind {
    init(_ folder: LibraryFolder) {
        switch folder {
        case .applicationSupport: self = .applicationSupport
        case .applicationScripts: self = .applicationScripts
        case .caches: self = .caches
        case .containers: self = .containers
        case .groupContainers: self = .groupContainers
        case .preferences: self = .preferences
        case .preferencesByHost: self = .preferencesByHost
        case .savedApplicationState: self = .savedApplicationState
        case .recentDocuments: self = .recentDocuments
        case .logs: self = .logs
        case .httpStorages: self = .httpStorages
        case .webKit: self = .webKit
        case .cookies: self = .cookies
        case .launchAgents: self = .launchAgents
        case .launchDaemons: self = .launchDaemons
        case .privilegedHelperTools: self = .privilegedHelperTools
        case .startupItems: self = .startupItems
        case .frameworks: self = .frameworks
        case .audioUnits, .audioDrivers, .vst, .vst3, .clap, .midiDrivers, .internetPlugIns, .preferencePanes,
            .quickLook,
             .screenSavers, .spotlight, .services, .inputMethods, .colorPickers, .contextualMenuItems, .mailBundles,
             .aax, .mas, .imageUnits, .dictionaries, .automatorActions, .contactsPlugIns:
            self = .plugIns
        }
    }

    /// True for code macOS loads, which is named for what it does rather than for who made it, and whose date does
    /// not move when it is used: a plug-in or a framework.
    var isLoadedCode: Bool {
        self == .plugIns || self == .frameworks
    }

    /// True when this kind of location looks at an entry with this name. The home folder is split in two: hidden
    /// entries, and the rest except the folders every account starts with.
    func considers(fileName: String) -> Bool {
        switch self {
        case .hiddenHomeFiles: fileName.hasPrefix(".")
        case .homeFolder: !fileName.hasPrefix(".") && !SearchEnvironment.accountFolderNames.contains(fileName.lowercased())
        default: true
        }
    }
}

public struct SearchEnvironment: Sendable {
    public var homeDirectory: URL
    public var rootDirectory: URL
    public var userCacheDirectory: URL?
    public var userTemporaryDirectory: URL?

    public init(
        homeDirectory: URL,
        rootDirectory: URL,
        userCacheDirectory: URL? = nil,
        userTemporaryDirectory: URL? = nil
    ) {
        self.homeDirectory = homeDirectory
        self.rootDirectory = rootDirectory
        self.userCacheDirectory = userCacheDirectory
        self.userTemporaryDirectory = userTemporaryDirectory
    }

    public static var current: SearchEnvironment {
        SearchEnvironment(
            homeDirectory: .homeDirectory,
            rootDirectory: URL(filePath: "/", directoryHint: .isDirectory),
            userCacheDirectory: darwinUserDirectory(_CS_DARWIN_USER_CACHE_DIR),
            userTemporaryDirectory: darwinUserDirectory(_CS_DARWIN_USER_TEMP_DIR)
        )
    }

    /// True for an app at `path` that a person keeps on its own. One inside the home's Library or the Mac's is part
    /// of another app (a helper, an agent, an update being prepared, a build) and goes with that app.
    func keepsOnItsOwn(appAt path: String) -> Bool {
        ![homeDirectory, rootDirectory].contains { folder in
            let library = folder.appending(path: "Library", directoryHint: .isDirectory)
            return PathComponents.isPath(path, inside: PathPattern.comparablePath(of: library))
        }
    }

    static let userEntries = LibraryFolder.user.map { (SearchLocation.Kind($0), $0.rawValue) }
    static let localEntries = LibraryFolder.local.map { (SearchLocation.Kind($0), $0.rawValue) }

    /// Lowercased, because disks ignore case by default, so `desktop` is the Desktop folder.
    static let accountFolderNames = Set(ProtectedData.accountFolders.map { $0.lowercased() })

    /// The first folder of every path the home's Library and the Mac's search as a location of their own, such as
    /// `Preferences`. The top of a Library never offers one of its own whole: it is looked inside, never moved. One
    /// only the other Library searches, such as `PrivilegedHelperTools` in the home's, is a folder like any other.
    static let homeLibraryEntriesScannedElsewhere = firstFolders(of: userEntries.map(\.1) + Plugins.folders.map(\.0))
    static let localLibraryEntriesScannedElsewhere = firstFolders(
        of: localEntries.map(\.1) + Plugins.folders.map(\.0) + systemCodeFolders
    )

    private static func firstFolders(of paths: [String]) -> Set<String> {
        Set(paths.map { String($0.prefix { $0 != "/" }) })
    }

    /// Where a driver's kernel extensions and a file system's bundles stay in `/Library`. They are searched like
    /// plug-ins, named for what they do, but the helper does not serve these folders, so what is found there is
    /// listed and never moved.
    static let systemCodeFolders = ["Extensions", "Filesystems"]

    public var locations: [SearchLocation] {
        let userLibrary = homeDirectory.appending(path: "Library", directoryHint: .isDirectory)
        let localLibrary = rootDirectory.appending(path: "Library", directoryHint: .isDirectory)

        var locations = Self.userEntries.map {
            SearchLocation(kind: $0.0, url: userLibrary.appending(path: $0.1, directoryHint: .isDirectory))
        }
        locations += Self.localEntries.map {
            SearchLocation(kind: $0.0, url: localLibrary.appending(path: $0.1, directoryHint: .isDirectory))
        }
        // The Plug-ins tool's own table, so the two cannot diverge.
        locations += [userLibrary, localLibrary].flatMap { library in
            Plugins.folders.map {
                SearchLocation(kind: .plugIns, url: library.appending(path: $0.0, directoryHint: .isDirectory))
            }
        }
        locations += Self.systemCodeFolders.map {
            SearchLocation(kind: .plugIns, url: localLibrary.appending(path: $0, directoryHint: .isDirectory))
        }
        if let userCacheDirectory {
            locations.append(SearchLocation(kind: .caches, url: userCacheDirectory))
        }
        if let userTemporaryDirectory {
            locations.append(SearchLocation(kind: .temporaryItems, url: userTemporaryDirectory))
        }
        // Homebrew links a cask's commands into its own `bin`: `/usr/local/bin` on Intel, `/opt/homebrew/bin` on
        // Apple silicon (Cask Cookbook, `binary`).
        locations += ["usr/local/bin", "usr/local/sbin", "opt/homebrew/bin"].map {
            SearchLocation(kind: .commandLineTools, url: rootDirectory.appending(path: $0, directoryHint: .isDirectory))
        }
        let hosts = [(userLibrary, Self.nativeMessagingHosts.user), (localLibrary, Self.nativeMessagingHosts.local)]
        locations += hosts.flatMap { library, folders in
            folders.map { library.appending(path: $0, directoryHint: .isDirectory) }
        }.map { SearchLocation(kind: .nativeMessagingHosts, url: $0) }
        locations.append(SearchLocation(kind: .safariWebApps, url: SafariWebApp.containers(inLibrary: userLibrary)))
        locations.append(SearchLocation(
            kind: .sharedFolder,
            url: rootDirectory.appending(path: "Users/Shared", directoryHint: .isDirectory)
        ))
        locations.append(SearchLocation(kind: .hiddenHomeFiles, url: homeDirectory))
        locations.append(SearchLocation(kind: .homeFolder, url: homeDirectory))
        locations += [
            SearchLocation(kind: .library, url: userLibrary, skipped: Self.homeLibraryEntriesScannedElsewhere),
            SearchLocation(kind: .library, url: localLibrary, skipped: Self.localLibraryEntriesScannedElsewhere),
        ]
        return locations
    }

    /// Each browser's own documentation: Chrome's and Chromium's "Native messaging", MDN's "Native manifests" for
    /// Firefox, and Microsoft's "Native messaging" for Edge and its Beta, Dev, and Canary channels.
    static let nativeMessagingHosts = (
        user: [
            "Application Support/Google/Chrome/NativeMessagingHosts",
            "Application Support/Chromium/NativeMessagingHosts",
            "Application Support/Mozilla/NativeMessagingHosts",
            "Application Support/Microsoft Edge/NativeMessagingHosts",
            "Application Support/Microsoft Edge Beta/NativeMessagingHosts",
            "Application Support/Microsoft Edge Dev/NativeMessagingHosts",
            "Application Support/Microsoft Edge Canary/NativeMessagingHosts",
        ],
        local: [
            "Google/Chrome/NativeMessagingHosts",
            "Application Support/Chromium/NativeMessagingHosts",
            "Application Support/Mozilla/NativeMessagingHosts",
            "Microsoft/Edge/NativeMessagingHosts",
        ]
    )

    private static func darwinUserDirectory(_ name: Int32) -> URL? {
        let length = confstr(name, nil, 0)
        guard length > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: length)
        guard confstr(name, &buffer, length) > 0 else { return nil }
        let path = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        return URL(filePath: path, directoryHint: .isDirectory)
    }
}
