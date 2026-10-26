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
    /// Why Peel would refuse to move it, such as a Mail bundle in the user's own Library, where all of Mail is
    /// protected. Such a plug-in is listed and never offered.
    public let refusal: GuardRefusal?
    /// True when, moved through Peel's helper, it could not come back from History: code is loaded from its folder,
    /// and it isn't root's alone (`PrivilegedPathPolicy.keepsOut`).
    public var staysInTheTrash = false

    public var id: URL { url }
}

extension Plugin.Category {
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

    /// Returns the `CFBundleIdentifier` in the plug-in's `Info.plist`. A plug-in is named for what it does, not
    /// for who made it, so this is its only identifier. It is only a claim, so callers match it like a file name.
    static func declaredIdentifier(at url: URL) -> String? {
        let contents = url.appending(path: "Contents", directoryHint: .isDirectory)
        return AppInspector.infoDictionary(in: contents)?["CFBundleIdentifier"] as? String
    }

    @concurrent
    public static func scan(
        environment: SearchEnvironment = .current,
        exclusions: Exclusions = .none
    ) async -> PluginScan {
        await scan(environment: environment, exclusions: exclusions, measure: FileSize.measure)
    }

    @concurrent
    static func scan(
        environment: SearchEnvironment,
        exclusions: Exclusions,
        measure: @escaping FileSize.Measure
    ) async -> PluginScan {
        let libraries = [
            (environment.homeDirectory.appending(path: "Library", directoryHint: .isDirectory), false),
            (environment.rootDirectory.appending(path: "Library", directoryHint: .isDirectory), true),
        ]
        var found: [(url: URL, category: Plugin.Category, isForAllUsers: Bool)] = []
        var unreadable: [URL] = []
        for (library, isForAllUsers) in libraries {
            for (folder, category) in folders {
                let directory = library.appending(path: folder, directoryHint: .isDirectory)
                for url in bundles(in: directory, category: category, unreadable: &unreadable)
                where !Task.isCancelled && !exclusions.excludes(url) && !exclusions.holds(url) {
                    found.append((url, category, isForAllUsers))
                }
            }
        }
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
                name: (info?["CFBundleName"] as? String) ?? item.url.deletingPathExtension().lastPathComponent,
                bundleIdentifier: info?["CFBundleIdentifier"] as? String,
                version: (info?["CFBundleShortVersionString"] ?? info?["CFBundleVersion"]) as? String,
                category: item.category,
                isInstalledForAllUsers: item.isForAllUsers,
                size: await measure(item.url),
                requiresPrivileges: requiresPrivileges,
                refusal: removalGuard.refusal(of: item.url)
            )
            plugin.staysInTheTrash = requiresPrivileges && reach.keepsOut(item.url, at: item.url)
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
