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
    /// True when Peel would refuse to move it, such as a Mail bundle in the user's own Library, where all of Mail
    /// is protected. It is listed and never offered.
    public let isLeftAlone: Bool

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
             .launchAgents, .launchDaemons, .privilegedHelperTools:
            return nil
        }
    }
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
    public static func scan(environment: SearchEnvironment = .current, exclusions: Exclusions = .none) async -> [Plugin] {
        await scan(environment: environment, exclusions: exclusions, measure: FileSize.measure)
    }

    @concurrent
    static func scan(environment: SearchEnvironment, exclusions: Exclusions, measure: FileSize.Measure) async -> [Plugin] {
        let libraries = [
            (environment.homeDirectory.appending(path: "Library", directoryHint: .isDirectory), false),
            (environment.rootDirectory.appending(path: "Library", directoryHint: .isDirectory), true),
        ]
        var plugins: [Plugin] = []
        let removalGuard = RemovalGuard(environment: environment, exclusions: exclusions)
        for (library, isForAllUsers) in libraries {
            for (folder, category) in folders {
                let directory = library.appending(path: folder, directoryHint: .isDirectory)
                for url in bundles(in: directory, category: category) where !Task.isCancelled && !exclusions.excludes(url) && !exclusions.holds(url) && !AppleCode.isApples(url) {
                    let info = AppInspector.infoDictionary(in: url.appending(path: "Contents", directoryHint: .isDirectory))
                    plugins.append(Plugin(
                        url: url,
                        name: (info?["CFBundleName"] as? String) ?? url.deletingPathExtension().lastPathComponent,
                        bundleIdentifier: info?["CFBundleIdentifier"] as? String,
                        version: (info?["CFBundleShortVersionString"] ?? info?["CFBundleVersion"]) as? String,
                        category: category,
                        isInstalledForAllUsers: isForAllUsers,
                        size: await measure(url),
                        requiresPrivileges: ParentAccess(url.deletingLastPathComponent()).requiresPrivileges(toRemove: url),
                        isLeftAlone: !removalGuard.allowsRemoval(of: url)
                    ))
                }
            }
        }
        return plugins.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
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
    /// themselves. A vendor can keep its plug-ins in a folder of its own, such as `VST3/<Company>/<Name>.vst3`.
    static func bundles(in directory: URL, category: Plugin.Category) -> [URL] {
        entries(of: directory).flatMap { url -> [URL] in
            if isPluginBundle(url, category: category) { return [url] }
            return isFolder(url) ? entries(of: url).filter { isPluginBundle($0, category: category) } : []
        }
    }

    private static func entries(of directory: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
    }

    private static func isFolder(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
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
