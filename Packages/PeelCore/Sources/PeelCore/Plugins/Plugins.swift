public import Foundation
internal import PeelPrivileged

public struct Plugin: Sendable, Hashable, Identifiable {
    public enum Category: String, Sendable, Hashable, CaseIterable {
        case audioUnits
        case audioDrivers
        case vst
        case vst3
        case clap
        case midiDrivers
        case internetPlugIns
        case preferencePanes
        case quickLook
        case screenSavers
        case spotlight
        case services
        case inputMethods
        case colorPickers
        case contextualMenuItems
        case mailBundles
        case aax
        case mas
        case imageUnits
        case dictionaries
        case automatorActions
        case contactsPlugIns
    }

    public let url: URL
    public let name: String
    public let bundleIdentifier: String?
    public let version: String?
    public let category: Category
    public let isInstalledForAllUsers: Bool
    /// Nil when measuring ran out of time or was refused. Unknown is not the same as empty.
    public let size: Int64?
    public let requiresPrivileges: Bool
    /// Why Peel would refuse to move it, such as an exclusion, exclusions not read yet, or a folder inside that macOS
    /// won't let Peel look into. Such a plug-in is listed and never offered.
    public let refusal: GuardRefusal?
    /// True when, moved through Peel's helper, it could not come back from History: code is loaded from its folder,
    /// and it isn't root's alone (the helper's `.loadsCode`).
    public var staysInTheTrash = false

    /// The app the plug-in came with, as Orphaned Files tells it.
    public enum Origin: Sendable, Hashable {
        case installedApp(name: String)
        /// An app Peel saw installed and then saw go.
        case goneApp(name: String)
    }

    public var origin: Origin?

    /// A kind of plug-in nothing on macOS loads anymore, so moving one changes nothing.
    public enum NoLongerLoaded: Sendable, Hashable {
        case quickLookGenerator
        /// An Internet plug-in other than a WebKit plug-in.
        case internetPlugIn
    }

    public var noLongerLoaded: NoLongerLoaded?

    public var id: URL { url }

    /// Whether it is an Automator workflow in a Services folder: a Quick Action, which an app may have put there or
    /// someone may have made on this Mac.
    public var isAQuickAction: Bool {
        category == .services && url.pathExtension.caseInsensitiveCompare("workflow") == .orderedSame
    }
}

extension Plugin.Category {
    /// The formats music apps and other hosts load on their own.
    var isLoadedByOtherApps: Bool {
        [.audioUnits, .vst, .vst3, .clap, .aax, .mas].contains(self)
    }

    init?(_ folder: LibraryFolder) {
        switch folder {
        case .audioUnits: self = .audioUnits
        case .audioDrivers: self = .audioDrivers
        case .vst: self = .vst
        case .vst3: self = .vst3
        case .clap: self = .clap
        case .midiDrivers: self = .midiDrivers
        case .internetPlugIns: self = .internetPlugIns
        case .preferencePanes: self = .preferencePanes
        case .quickLook: self = .quickLook
        case .screenSavers: self = .screenSavers
        case .spotlight: self = .spotlight
        case .services: self = .services
        case .inputMethods: self = .inputMethods
        case .colorPickers: self = .colorPickers
        case .contextualMenuItems: self = .contextualMenuItems
        case .mailBundles: self = .mailBundles
        case .aax: self = .aax
        case .mas: self = .mas
        case .imageUnits: self = .imageUnits
        case .dictionaries: self = .dictionaries
        case .automatorActions: self = .automatorActions
        case .contactsPlugIns: self = .contactsPlugIns
        case .applicationSupport, .applicationScripts, .caches, .containers, .groupContainers, .preferences,
             .preferencesByHost, .savedApplicationState, .recentDocuments, .logs, .httpStorages, .webKit, .cookies,
             .launchAgents, .launchDaemons, .privilegedHelperTools, .startupItems, .frameworks:
            return nil
        }
    }
}

/// The plug-ins one scan found, and the folders it couldn't read, which may hold more.
public struct PluginScan: Sendable {
    public var plugins: [Plugin] = []
    public var unreadable: [URL] = []
    /// True when macOS's privacy protection kept Peel out of one of them, which Full Disk Access lifts.
    public var needsFullDiskAccess = false
}

/// Finds the plug-ins that apps have installed in the folders macOS loads plug-ins from. Apple's own
/// components sit in the same folders and are left out, because macOS relies on them.
public enum Plugins {
    /// The folders in each Library that macOS loads plug-ins from, with what each holds. `SearchEnvironment` reuses
    /// this table, so the uninstall and Orphaned Files search these folders.
    static let folders = LibraryFolder.plugIns.compactMap { folder in
        Plugin.Category(folder).map { (folder.rawValue, $0) }
    }

    /// The folders of plug-ins music apps and other hosts load on their own, in the home's Library and the Mac's,
    /// worked out once for a scan that asks about each of its items.
    struct LoadedByOtherApps: Sendable {
        /// Each folder's names, split once.
        private let places: [[String]]

        init(environment: SearchEnvironment) {
            let names = Plugins.folders.filter { $0.1.isLoadedByOtherApps }.map(\.0)
            places = [environment.homeDirectory, environment.rootDirectory].flatMap { base in
                names.map { PathComponents.of(PathPattern.comparablePath(of: base.appending(path: "Library/\($0)"))) }
            }
        }

        /// Whether `url` is inside one of these folders, as `PathComponents.isPath(_:inside:)` tells.
        func holds(_ url: URL) -> Bool {
            let names = PathComponents.of(PathPattern.comparablePath(of: url))
            return places.contains { names.count > $0.count && names.starts(with: $0) }
        }
    }

    /// An installed app with what the matcher knows of it, made once per scan, since each plug-in is asked about every
    /// app.
    struct Claimant: Sendable {
        let name: String
        let profile: LeftoverMatcher.Profile

        init(_ app: InstalledApp) {
            name = app.name
            profile = LeftoverMatcher.Profile(app)
        }
    }

    /// The app a plug-in came with: an installed app that claims it surely, through the identifier it declares or,
    /// for one that declares none, through its name, since a name its identifier doesn't back says nothing; else the
    /// app Peel saw go whose identifier it has, extends, or shares a maker with, as Orphaned Files lists it.
    static func origin(
        of url: URL, identifier: String?, claimants: [Claimant], goneApps: [RememberedApp]
    ) -> Plugin.Origin? {
        let name = LeftoverMatcher.key(from: url.lastPathComponent, kind: .plugIns)
        let candidate = LeftoverMatcher.Candidate(identifier ?? name)
        let claims = claimants.compactMap { app in
            app.profile.claim(for: candidate).map { (name: app.name, evidence: $0) }
        }
        let sure = claims.filter { $0.evidence.confidence != .possible }
        if let app = sure.max(by: { $0.evidence.rank < $1.evidence.rank }) {
            return .installedApp(name: app.name)
        }
        guard let identifier else { return nil }
        let plugIn = identifier.lowercased()
        let gone = goneApps.first { app in
            let own = app.bundleIdentifier.lowercased()
            return plugIn == own || plugIn.hasPrefix(own + ".")
        } ?? goneApps.first { app in
            OrphanScanner.cameWithAnAppThatLeft(identifier, goneApps: [app.bundleIdentifier.lowercased()])
        }
        return gone.map { .goneApp(name: $0.name) }
    }

    /// Returns the `CFBundleIdentifier` in the plug-in's `Info.plist`. A plug-in is named for what it does, not
    /// for who made it, so this is its only identifier. It is only a claim, so callers match it like a file name.
    static func declaredIdentifier(at url: URL) -> String? {
        let contents = url.appending(path: "Contents", directoryHint: .isDirectory)
        return AppInspector.infoDictionary(in: contents)?["CFBundleIdentifier"] as? String
    }

    /// Reads the plug-ins, each with the app it came with, from the apps in the environment's Applications folders and
    /// those Peel remembers.
    @concurrent
    public static func scan(
        environment: SearchEnvironment = .current,
        exclusions: Exclusions = .none
    ) async -> PluginScan {
        await scan(
            environment: environment,
            exclusions: exclusions,
            installedApps: await AppCatalog.installedApps(in: AppCatalog.directories(in: environment)),
            remembered: await AppMemory(url: AppMemory.url(inHome: environment.homeDirectory)).load(),
            measure: FileSize.measure
        )
    }

    @concurrent
    static func scan(
        environment: SearchEnvironment,
        exclusions: Exclusions,
        installedApps: [InstalledApp] = [],
        remembered: [RememberedApp] = [],
        measure: @escaping FileSize.Measure
    ) async -> PluginScan {
        let (apps, goneApps) = OrphanScanner.split(remembered, installedApps: installedApps)
        let claimants = apps.map(Claimant.init)
        var unreadable: [URL] = []
        let found = installed(in: environment, unreadable: &unreadable)
            .filter { !exclusions.excludes($0.url) && !exclusions.holds($0.url) }
        // A few at a time, as the other scans measure: the guard's answer and the size each take a while, and a Mac
        // used for music can hold more than a thousand plug-ins.
        let removalGuard = RemovalGuard(environment: environment, exclusions: exclusions)
        let reach = HelperReach(environment: environment)
        let plugins = await found.concurrentMap(width: LeftoverScanner.concurrentMeasurements) { item -> Plugin? in
            guard !AppleCode.isApples(item.url) else { return nil }
            let info = AppInspector.infoDictionary(in: item.url.appending(path: "Contents", directoryHint: .isDirectory))
            let folder = ParentAccess(item.url.deletingLastPathComponent())
            let requiresPrivileges = folder.requiresPrivileges(toRemove: item.url)
            var plugin = Plugin(
                url: item.url,
                name: name(of: item.url, info: info),
                bundleIdentifier: info?["CFBundleIdentifier"] as? String,
                version: (info?["CFBundleShortVersionString"] ?? info?["CFBundleVersion"]) as? String,
                category: item.category,
                isInstalledForAllUsers: item.isForAllUsers,
                size: await measure(item.url),
                requiresPrivileges: requiresPrivileges,
                refusal: removalGuard.refusal(of: item.url)
            )
            plugin.staysInTheTrash = requiresPrivileges
                && reach.refusal(ofPuttingBack: item.url, at: item.url) == .loadsCode
            plugin.noLongerLoaded = noLongerLoaded(item.url, category: item.category)
            plugin.origin = origin(
                of: item.url, identifier: plugin.bundleIdentifier, claimants: claimants, goneApps: goneApps
            )
            return plugin
        }
        let sorted = plugins.compactMap(\.self).sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        return PluginScan(
            plugins: sorted,
            unreadable: unreadable,
            needsFullDiskAccess: unreadable.contains { FullDiskAccess.canList($0) == .missing }
        )
    }

    /// Whether nothing on macOS loads the plug-in anymore. macOS no longer loads a Quick Look generator from another
    /// maker (macOS 15 Release Notes), and from an Internet Plug-Ins folder WebKit loads only a WebKit plug-in, named
    /// `.webplugin` or of package type `WBPL` as `CFBundleGetPackageInfo` reads it, while browsers load none.
    static func noLongerLoaded(_ url: URL, category: Plugin.Category) -> Plugin.NoLongerLoaded? {
        switch category {
        case .quickLook:
            return url.pathExtension.caseInsensitiveCompare("qlgenerator") == .orderedSame ? .quickLookGenerator : nil
        case .internetPlugIns:
            guard url.pathExtension.caseInsensitiveCompare("webplugin") != .orderedSame else { return nil }
            var type: UInt32 = 0
            if let bundle = CFBundleCreate(nil, url as CFURL) {
                CFBundleGetPackageInfo(bundle, &type, nil)
            }
            return type == webKitPlugInType ? nil : .internetPlugIn
        default:
            return nil
        }
    }

    private static let webKitPlugInType = "WBPL".utf8.reduce(UInt32(0)) { $0 << 8 | UInt32($1) }

    /// The plug-ins in the user's Library and the Mac's, each with its kind and whether it is there for every account.
    /// A folder that is there and can't be listed joins `unreadable`.
    static func installed(
        in environment: SearchEnvironment, unreadable: inout [URL]
    ) -> [(url: URL, category: Plugin.Category, isForAllUsers: Bool)] {
        let libraries = [
            (environment.homeDirectory.appending(path: "Library", directoryHint: .isDirectory), false),
            (environment.rootDirectory.appending(path: "Library", directoryHint: .isDirectory), true),
        ]
        var found: [(url: URL, category: Plugin.Category, isForAllUsers: Bool)] = []
        for (library, isForAllUsers) in libraries {
            for (folder, category) in folders {
                let directory = library.appending(path: folder, directoryHint: .isDirectory)
                for url in bundles(in: directory, category: category, unreadable: &unreadable) where !Task.isCancelled {
                    found.append((url, category, isForAllUsers))
                }
            }
        }
        return found
    }

    /// The name a plug-in shows: the one its bundle declares, in the Mac's language when the bundle has it, or its
    /// file's without the extension that says its kind. A workflow shows the name it has in the Services menu
    /// (`NSServices`, `NSMenuItem`), as the person knows it.
    static func name(of url: URL, info: [String: Any]?) -> String {
        if url.pathExtension.caseInsensitiveCompare("workflow") == .orderedSame,
           let item = (info?["NSServices"] as? [[String: Any]])?.first?["NSMenuItem"] as? [String: Any],
           let menuName = item["default"] as? String, !menuName.isEmpty {
            return menuName
        }
        // `Bundle` reads a bundle without registering it with Launch Services, unlike asking for its display name.
        let localized = Bundle(url: url)?.localizedInfoDictionary
        let declared = [localized?["CFBundleDisplayName"], localized?["CFBundleName"], info?["CFBundleName"]]
            .lazy.compactMap { ($0 as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty }
        return declared ?? url.deletingPathExtension().lastPathComponent
    }

    /// The file extensions each kind of plug-in uses.
    static let extensions: [Plugin.Category: Set<String>] = [
        .audioUnits: ["component"],
        .audioDrivers: ["driver", "plugin", "bundle"],
        .vst: ["vst"],
        .vst3: ["vst3"],
        .clap: ["clap"],
        .midiDrivers: ["plugin", "driver", "bundle"],
        .internetPlugIns: ["plugin", "webplugin", "bundle"],
        .preferencePanes: ["prefpane"],
        .quickLook: ["qlgenerator", "appex"],
        .screenSavers: ["saver", "appex"],
        .spotlight: ["mdimporter"],
        .services: ["workflow", "service", "app"],
        .inputMethods: ["app", "inputmethod", "bundle"],
        .colorPickers: ["colorpicker"],
        .contextualMenuItems: ["plugin"],
        .mailBundles: ["mailbundle"],
        .aax: ["aaxplugin"],
        .mas: ["bundle"],
        .imageUnits: ["plugin"],
        .dictionaries: ["dictionary"],
        .automatorActions: ["action"],
        .contactsPlugIns: ["bundle"],
    ]

    /// Returns the plug-ins in `directory`, looking one level down inside folders that are not plug-ins
    /// themselves. A vendor can keep its plug-ins in a folder of its own, such as `VST3/<Company>/<Name>.vst3`. A
    /// folder that is there and can't be listed joins `unreadable`.
    static func bundles(in directory: URL, category: Plugin.Category, unreadable: inout [URL]) -> [URL] {
        entries(of: directory, unreadable: &unreadable).flatMap { url -> [URL] in
            if isPluginBundle(url, category: category) { return [url] }
            guard isFolder(url) else { return [] }
            return entries(of: url, unreadable: &unreadable).filter { isPluginBundle($0, category: category) }
        }
    }

    /// The entries of `directory`, through a link to a folder as the apps that load plug-ins go through one.
    private static func entries(of directory: URL, unreadable: inout [URL]) -> [URL] {
        guard isFolder(directory) else { return [] }
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))
        else {
            unreadable.append(directory)
            return []
        }
        ScanCount.current?.add(names.count)
        return names.map { directory.appending(path: $0) }
    }

    /// Whether `url` is a folder, or a link to one.
    private static func isFolder(_ url: URL) -> Bool {
        var info = stat()
        return stat(url.path(percentEncoded: false), &info) == 0 && info.st_mode & S_IFMT == S_IFDIR
    }

    /// Whether `url` is a plug-in for `category`: a folder with one of the category's extensions, or any other
    /// folder with an extension and a `Contents` folder inside. That second rule finds plug-ins whose extension
    /// is not listed, and keeps out a vendor's folder such as `Vendor 14.0`, whose extension is `0`.
    static func isPluginBundle(_ url: URL, category: Plugin.Category) -> Bool {
        guard !url.pathExtension.isEmpty, !url.lastPathComponent.hasPrefix("."), isFolder(url) else { return false }
        if extensions[category]?.contains(url.pathExtension.lowercased()) == true { return true }
        return isFolder(url.appending(path: "Contents", directoryHint: .isDirectory))
    }
}
