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
        /// The folders macOS loads plug-ins from.
        case plugIns
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
        /// Somewhere no scan looks, which only a Homebrew cask can name: `~/Documents/Foo`, `/usr/local/etc/foo`.
        case elsewhere
    }

    public let kind: Kind
    public let url: URL

    public init(kind: Kind, url: URL) {
        self.kind = kind
        self.url = url
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
        case .audioUnits, .audioDrivers, .vst, .vst3, .clap, .midiDrivers, .internetPlugIns, .preferencePanes, .quickLook,
             .screenSavers, .spotlight, .services, .inputMethods, .colorPickers, .contextualMenuItems, .mailBundles,
             .aax, .mas, .imageUnits, .dictionaries, .automatorActions, .contactsPlugIns:
            self = .plugIns
        }
    }

    /// True when this kind of location looks at an entry with this name. The home folder is split in two: hidden
    /// entries, and the rest except the folders every account starts with. At the top of a Library, a folder
    /// scanned as a location of its own is never offered whole.
    func considers(fileName: String) -> Bool {
        switch self {
        case .hiddenHomeFiles: fileName.hasPrefix(".")
        case .homeFolder: !fileName.hasPrefix(".") && !SearchEnvironment.accountFolderNames.contains(fileName.lowercased())
        case .library: !SearchEnvironment.libraryEntriesScannedElsewhere.contains(fileName)
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

    static let userEntries = LibraryFolder.user.map { (SearchLocation.Kind($0), $0.rawValue) }
    static let localEntries = LibraryFolder.local.map { (SearchLocation.Kind($0), $0.rawValue) }

    /// Lowercased, because disks ignore case by default, so `desktop` is the Desktop folder.
    static let accountFolderNames = Set(ProtectedData.accountFolders.map { $0.lowercased() })

    /// The first folder of every Library path scanned as a location of its own, such as `Preferences`. The top of
    /// a Library never offers one of these whole: they are looked inside, never moved.
    static let libraryEntriesScannedElsewhere = Set(
        ((userEntries + localEntries).map(\.1) + Plugins.folders.map(\.0) + [kernelExtensions]).map { name in
            String(name.prefix { $0 != "/" })
        }
    )

    /// Where a driver's kernel extensions stay in `/Library`. They are searched like plug-ins, named for what they
    /// do, but the helper does not serve this folder, so what is found there is listed and never moved.
    static let kernelExtensions = "Extensions"

    public var locations: [SearchLocation] {
        let userLibrary = homeDirectory.appending(path: "Library", directoryHint: .isDirectory)
        let localLibrary = rootDirectory.appending(path: "Library", directoryHint: .isDirectory)

        var locations = Self.userEntries.map { SearchLocation(kind: $0.0, url: userLibrary.appending(path: $0.1, directoryHint: .isDirectory)) }
        locations += Self.localEntries.map { SearchLocation(kind: $0.0, url: localLibrary.appending(path: $0.1, directoryHint: .isDirectory)) }
        // The Plug-ins tool's own table, so the two cannot diverge.
        locations += [userLibrary, localLibrary].flatMap { library in
            Plugins.folders.map { SearchLocation(kind: .plugIns, url: library.appending(path: $0.0, directoryHint: .isDirectory)) }
        }
        locations.append(SearchLocation(
            kind: .plugIns, url: localLibrary.appending(path: Self.kernelExtensions, directoryHint: .isDirectory)
        ))
        if let userCacheDirectory {
            locations.append(SearchLocation(kind: .caches, url: userCacheDirectory))
        }
        if let userTemporaryDirectory {
            locations.append(SearchLocation(kind: .temporaryItems, url: userTemporaryDirectory))
        }
        locations += ["usr/local/bin", "usr/local/sbin"].map {
            SearchLocation(kind: .commandLineTools, url: rootDirectory.appending(path: $0, directoryHint: .isDirectory))
        }
        locations.append(SearchLocation(
            kind: .sharedFolder,
            url: rootDirectory.appending(path: "Users/Shared", directoryHint: .isDirectory)
        ))
        locations.append(SearchLocation(kind: .hiddenHomeFiles, url: homeDirectory))
        locations.append(SearchLocation(kind: .homeFolder, url: homeDirectory))
        locations += [userLibrary, localLibrary].map { SearchLocation(kind: .library, url: $0) }
        return locations
    }

    private static func darwinUserDirectory(_ name: Int32) -> URL? {
        let length = confstr(name, nil, 0)
        guard length > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: length)
        guard confstr(name, &buffer, length) > 0 else { return nil }
        let path = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        return URL(filePath: path, directoryHint: .isDirectory)
    }
}
