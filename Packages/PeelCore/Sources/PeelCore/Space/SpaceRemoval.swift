import AppKit
public import Foundation

/// Plans the emptying of one of Space's folders. The folder itself is never removed (the guard refuses it, and
/// macOS expects to find it), so its children are listed instead, and inside a vendor's folder that holds a tool's
/// own, the vendor's other children. Each passes through the same guard and exclusions as anything else, and one
/// named for an open app is left where it is, since the app may still be writing to it.
public enum SpaceRemoval {
    public struct Plan: Sendable {
        /// Folders and files that will be moved to the Trash.
        public let removable: [URL]
        /// Those left alone because the app that owns them is open, each with the name of that app.
        public let inUse: [(url: URL, name: String)]
        /// Folders left to Developer, each a tool's own folder with something inside that Developer lists.
        public let leftToDeveloper: [URL]
        /// The size of each removable item, which is what emptying frees. One whose size is not known is missing
        /// here but stays in `removable`.
        public let sizes: [URL: Int64]
        /// Why a removable item is left for the person to choose, from what measuring it saw. One missing here holds
        /// nothing that keeps it from being selected.
        public var heldBack: [URL: HoldBack] = [:]
        /// The removable items only an administrator can move, which go through the helper.
        public var needsTheHelper: Set<URL> = []

        /// The open apps whose folders are left alone, each named once and sorted, by the names the user knows, not
        /// the folder names. One app can write to several folders, by its name and by its identifier.
        public var appsToQuit: [String] {
            Set(inUse.map(\.name)).sorted()
        }

        /// What Peel selects of this plan for the person: every item it could measure that nothing holds back.
        public var suggested: Set<URL> {
            Set(sizes.keys).subtracting(heldBack.keys)
        }
    }

    /// The plan while the apps in `running` are open, whose names and groups are read here, away from the main actor.
    @concurrent
    public static func plan(
        for item: SpaceItem,
        environment: SearchEnvironment = .current,
        exclusions: Exclusions = .none,
        running: [RunningCopies.Process]
    ) async -> Plan {
        await plan(for: item, environment: environment, exclusions: exclusions, running: namesOfRunningApps(running))
    }

    @concurrent
    static func plan(
        for item: SpaceItem,
        environment: SearchEnvironment,
        exclusions: Exclusions = .none,
        running: [String: String] = [:],
        measure: LeftoverScanner.Measure = LeftoverScanner.walk
    ) async -> Plan {
        let children = children(of: item, environment: environment, exclusions: exclusions, running: running)
        let systemCaches = SystemCaches(environment: environment)
        let reach = HelperReach(environment: environment)
        var sizes: [URL: Int64] = [:]
        var heldBack: [URL: HoldBack] = [:]
        var needsTheHelper: Set<URL> = []
        for child in children.removable where !Task.isCancelled {
            let contents = await measure(child)
            sizes[child] = contents.flatMap { $0.couldNotBeRead ? nil : $0.size }
            let needsAnAdministrator = FileAccess.requiresPrivilegesToRemove(child)
            if needsAnAdministrator { needsTheHelper.insert(child) }
            let beyond: HoldBack? = needsAnAdministrator && reach.isBeyond(child) ? .beyondTheHelper : nil
            heldBack[child] = beyond ?? item.heldBack
                ?? (systemCaches.keeps(child) ? .keptByMacOS : HoldBack.seen(in: contents))
        }
        return Plan(
            removable: children.removable, inUse: children.inUse, leftToDeveloper: children.leftToDeveloper, sizes: sizes,
            heldBack: heldBack, needsTheHelper: needsTheHelper
        )
    }

    /// What of `item` can move now, measuring nothing: the check a move makes just before it moves, since an app
    /// opened since the plan may be writing to some of these folders.
    @concurrent
    public static func removable(
        in item: SpaceItem,
        environment: SearchEnvironment = .current,
        exclusions: Exclusions = .none,
        running: [RunningCopies.Process]
    ) async -> [URL] {
        await removable(
            in: item, environment: environment, exclusions: exclusions, running: namesOfRunningApps(running)
        )
    }

    @concurrent
    static func removable(
        in item: SpaceItem,
        environment: SearchEnvironment,
        exclusions: Exclusions = .none,
        running: [String: String] = [:]
    ) async -> [URL] {
        children(of: item, environment: environment, exclusions: exclusions, running: running).removable
    }

    private static func children(
        of item: SpaceItem,
        environment: SearchEnvironment,
        exclusions: Exclusions,
        running: [String: String]
    ) -> (removable: [URL], inUse: [(url: URL, name: String)], leftToDeveloper: [URL]) {
        let removalGuard = RemovalGuard(environment: environment, exclusions: exclusions)
        var removable: [URL] = []
        var inUse: [(url: URL, name: String)] = []
        var leftToDeveloper: [URL] = []
        let systemCaches = SystemCaches(environment: environment)
        func sort(_ folder: URL, leaving owned: [[String]], owner: String?) {
            let children = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            for child in children ?? [] {
                let name = child.lastPathComponent
                if item.leavesMacOSsOwn, SystemCaches.isMacOSs(name) { continue }
                let app = owner ?? running[Naming.normalized(name)]
                let listed = owned.filter { fnmatch($0[0], name, FNM_CASEFOLD) == 0 }
                if app == nil, !listed.isEmpty, !listed.contains(where: { $0.count == 1 }), child.isRealFolder {
                    sort(child, leaving: listed.map { Array($0.dropFirst()) }, owner: owner)
                    continue
                }
                guard removalGuard.allowsRemoval(of: child) else { continue }
                if let app {
                    inUse.append((child, app))
                } else if !listed.isEmpty {
                    leftToDeveloper.append(child)
                } else {
                    removable.append(child)
                }
            }
        }
        for url in item.urls {
            // Everything in an app's container is that app's, whatever its name.
            let owner = systemCaches.container(holding: url).flatMap { running[Naming.normalized($0)] }
            let owned = DeveloperCaches.foldersLeftToDeveloper(inside: url, home: environment.homeDirectory)
            sort(url, leaving: owned, owner: owner)
        }
        return (removable, inUse, leftToDeveloper)
    }

    /// Maps each name an open app answers to, normalized, to the app's display name. The names are the bundle
    /// identifier, its last part, and the bundle's file name, since many cache and log folders carry the app's
    /// name rather than its identifier (`Firefox`, `Zed`), and the application groups its signature claims, whose
    /// group containers it shares with other apps of its maker.
    static func namesOfRunningApps(_ running: [RunningCopies.Process]) -> [String: String] {
        var names: [String: String] = [:]
        for process in running {
            let bundle = process.bundleURL?.deletingPathExtension().lastPathComponent
            // Folders on disk carry the bundle's file name. The user sees the app's name as Finder shows it.
            let displayed = process.bundleURL.map(AppInspector.displayName) ?? process.bundleIdentifier
            let spellings = [
                process.bundleIdentifier,
                process.bundleIdentifier.split(separator: ".").last.map(String.init),
                bundle,
            ].compactMap(\.self) + (process.bundleURL.map(AppInspector.applicationGroups) ?? [])
            for spelling in spellings where Naming.isSignificant(spelling) {
                names[Naming.normalized(spelling)] = displayed
            }
        }
        return names
    }

}
