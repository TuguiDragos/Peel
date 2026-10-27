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
        /// The size of each folder left to Developer (`sizesLeftToDeveloper(in:)`), nil until they are measured, apart
        /// from the plan, so a page lists what it can move without waiting for them.
        public var developerSizes: [URL: Int64]?
        /// The size of each folder an open app keeps or the guard refuses (`sizesKeptInPlace(in:)`), measured with
        /// those left to Developer, nil until then.
        public var keptSizes: [URL: Int64]?
        /// Why a removable item is left for the person to choose, from what measuring it saw. One missing here holds
        /// nothing that keeps it from being selected.
        public var heldBack: [URL: HoldBack] = [:]
        /// The removable items only an administrator can move, which go through the helper.
        public var needsTheHelper: Set<URL> = []
        /// What the guard never moves from here, each with its reason, so the page can say why the area holds more
        /// than it offers. What the person excluded is left out, as it is everywhere.
        public var refused: [URL: GuardRefusal] = [:]
        /// The folders Peel couldn't look into, so the area may hold more than the plan offers.
        public var unreadable: [URL] = []
        /// True when macOS's privacy protection kept Peel out of one of them, which Full Disk Access lifts.
        public var needsFullDiskAccess = false

        /// The open apps whose folders are left alone, each named once and sorted, by the names the user knows, not
        /// the folder names. One app can write to several folders, by its name and by its identifier.
        public var appsToQuit: [String] {
            Set(inUse.map(\.name)).sorted()
        }

        /// What Peel recommends of this plan, which Select Recommended selects: every item it could measure that
        /// nothing holds back.
        public var suggested: Set<URL> {
            Set(sizes.keys).subtracting(heldBack.keys)
        }

        /// One the helper would refuse anyway is left alone rather than locked.
        public func isLocked(_ url: URL, canUseHelper: Bool) -> Bool {
            needsTheHelper.contains(url) && heldBack[url]?.cannotBeMoved != true && !canUseHelper
        }

        /// What stays selected in the area as the plan is made again or the helper comes or goes: what the person
        /// chose that can still be selected. Nothing is selected for them.
        public func selection(keeping selected: Set<URL>, canUseHelper: Bool) -> Set<URL> {
            selected.intersection(selectableRows(canUseHelper: canUseHelper).selectable)
        }

        /// What the area holds as this plan sees it, from the same moment as what it can move, or nil until what it
        /// doesn't offer is measured.
        public var seen: SizeTotal? {
            guard let developerSizes, let keptSizes else { return nil }
            let kept = inUse.map(\.url) + refused.keys
            return SizeTotal(
                removable.map { sizes[$0] } + leftToDeveloper.map { developerSizes[$0] } + kept.map { keptSizes[$0] }
                    + unreadable.map { _ -> Int64? in nil }
            )
        }

        /// What the page can move now, which its total says: the rows a checkbox can select, and as unknown each
        /// folder Peel couldn't look into, since it may hold more.
        public func movable(canUseHelper: Bool) -> SizeTotal {
            let rows = selectableRows(canUseHelper: canUseHelper).selectable
            return SizeTotal(rows.map { sizes[$0] } + unreadable.map { _ -> Int64? in nil })
        }

        public func selectableRows(canUseHelper: Bool) -> SelectableRows<URL> {
            let unlocked = removable.filter { !isLocked($0, canUseHelper: canUseHelper) }
            return SelectableRows(
                rows: removable,
                selectable: unlocked.filter { heldBack[$0]?.cannotBeMoved != true },
                recommended: unlocked.filter(suggested.contains)
            )
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
        await plan(
            for: item, environment: environment, exclusions: exclusions,
            running: namesOfRunningApps(running.filter { $0.identifier != getpid() }), own: peelsOwnNames(running)
        )
    }

    @concurrent
    static func plan(
        for item: SpaceItem,
        environment: SearchEnvironment,
        exclusions: Exclusions = .none,
        running: [String: String] = [:],
        own: Set<String> = [],
        measure: @escaping LeftoverScanner.Measure = LeftoverScanner.walk
    ) async -> Plan {
        let children = children(
            of: item, environment: environment, exclusions: exclusions, running: running, own: own
        )
        let macOSsOwn = MacOSsOwnItems(environment: environment)
        let reach = HelperReach(environment: environment)
        var sizes: [URL: Int64] = [:]
        var heldBack: [URL: HoldBack] = [:]
        var needsTheHelper: Set<URL> = []
        let measured = await children.removable.concurrentMap(width: LeftoverScanner.concurrentMeasurements) { child in
            (child, await measure(child))
        }
        for child in children.closed {
            heldBack[child] = .couldNotLookInside
        }
        for (child, contents) in measured {
            sizes[child] = contents.flatMap { $0.couldNotBeRead ? nil : $0.size }
            let needsAnAdministrator = FileAccess.requiresPrivilegesToRemove(child)
            if needsAnAdministrator { needsTheHelper.insert(child) }
            let beyond: HoldBack? = needsAnAdministrator && reach.isBeyond(child) ? .beyondTheHelper : nil
            heldBack[child] = beyond ?? item.heldBack
                ?? (macOSsOwn.contains(child) ? .keptByMacOS : HoldBack.seen(in: contents))
                ?? (item.holdsBackRecentWrites && HoldBack.wasWrittenRecently(child, contents: contents)
                    ? .writtenRecently : nil)
        }
        return Plan(
            removable: children.removable + children.closed,
            inUse: children.inUse,
            leftToDeveloper: children.leftToDeveloper,
            sizes: sizes,
            heldBack: heldBack, needsTheHelper: needsTheHelper, refused: children.refused,
            unreadable: children.unreadable,
            needsFullDiskAccess: children.unreadable.contains { FullDiskAccess.canList($0) == .missing }
        )
    }

    @concurrent
    public static func sizesKeptInPlace(in plan: Plan) async -> [URL: Int64] {
        await sizes(of: plan.inUse.map(\.url) + plan.refused.keys)
    }

    @concurrent
    public static func sizesLeftToDeveloper(in plan: Plan) async -> [URL: Int64] {
        await sizes(of: plan.leftToDeveloper)
    }

    private static func sizes(of folders: [URL]) async -> [URL: Int64] {
        let measured = await folders.concurrentMap(width: LeftoverScanner.concurrentMeasurements) { folder in
            (folder, await LeftoverScanner.walk(folder))
        }
        var sizes: [URL: Int64] = [:]
        for (folder, contents) in measured {
            sizes[folder] = contents.flatMap { $0.couldNotBeRead ? nil : $0.size }
        }
        return sizes
    }

    /// What of `item` can move now, measuring nothing, and what an app open now keeps: the check a move makes just
    /// before it moves, since an app opened since the plan may be writing to some of these folders.
    @concurrent
    public static func movableNow(
        in item: SpaceItem,
        environment: SearchEnvironment = .current,
        exclusions: Exclusions = .none,
        running: [RunningCopies.Process]
    ) async -> (removable: [URL], inUse: [(url: URL, name: String)]) {
        await movableNow(
            in: item, environment: environment, exclusions: exclusions,
            running: namesOfRunningApps(running.filter { $0.identifier != getpid() }), own: peelsOwnNames(running)
        )
    }

    @concurrent
    static func movableNow(
        in item: SpaceItem,
        environment: SearchEnvironment,
        exclusions: Exclusions = .none,
        running: [String: String] = [:],
        own: Set<String> = []
    ) async -> (removable: [URL], inUse: [(url: URL, name: String)]) {
        let children = children(
            of: item, environment: environment, exclusions: exclusions, running: running, own: own
        )
        return (children.removable, children.inUse)
    }

    private static func children(
        of item: SpaceItem,
        environment: SearchEnvironment,
        exclusions: Exclusions,
        running: [String: String],
        own: Set<String>
    ) -> (
        removable: [URL], inUse: [(url: URL, name: String)], leftToDeveloper: [URL], refused: [URL: GuardRefusal],
        unreadable: [URL], closed: [URL]
    ) {
        // An area only its own app or tool should empty, such as a virtual machine's disks, offers nothing.
        guard item.handling == .trash else { return ([], [], [], [:], [], []) }
        let removalGuard = RemovalGuard(environment: environment, exclusions: exclusions)
        var removable: [URL] = []
        var inUse: [(url: URL, name: String)] = []
        var leftToDeveloper: [URL] = []
        var refused: [URL: GuardRefusal] = [:]
        var unreadable: [URL] = []
        var closed: [URL] = []
        let macOSsOwn = MacOSsOwnItems(environment: environment)
        let filesOnly = Set(item.onlyFilesIn.map(PathPattern.comparablePath))
        func sort(_ folder: URL, leaving owned: [[String]], owner: String?, onlyFiles inside: Bool = false) {
            guard let children = try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: nil
            ) else {
                if !folder.isMissing { unreadable.append(folder) }
                return
            }
            let onlyFiles = inside || filesOnly.contains(PathPattern.comparablePath(of: folder))
            for child in children {
                let name = child.lastPathComponent
                if item.leavesMacOSsOwn, SpaceInventory.isMacOSsOwn(name) { continue }
                if own.contains(Naming.normalized(name)) { continue }
                if onlyFiles, child.isRealFolder { continue }
                let app = owner ?? running[Naming.normalized(name)]
                let listed = owned.filter { fnmatch($0[0], name, FNM_CASEFOLD) == 0 }
                if item.keepsItsFolders, child.isRealFolder, !listed.contains(where: { $0.count == 1 }) {
                    sort(child, leaving: listed.map { Array($0.dropFirst()) }, owner: app, onlyFiles: true)
                    continue
                }
                if app == nil, !listed.isEmpty, !listed.contains(where: { $0.count == 1 }), child.isRealFolder {
                    sort(child, leaving: listed.map { Array($0.dropFirst()) }, owner: owner)
                    continue
                }
                switch removalGuard.refusal(of: child) {
                case .excluded, .exclusionsNotKnown:
                    continue
                // Developer lists the parts of a tool's folder that are only a cache, and never the rest.
                case _? where !listed.isEmpty:
                    leftToDeveloper.append(child)
                    continue
                // A folder that stays itself is one Space empties on its own page, or one macOS expects to find.
                case .staysItself:
                    continue
                // Listed and left alone with its reason, as on every page: it may hold what Peel never moves.
                case .couldNotLookInside:
                    closed.append(child)
                    continue
                case let refusal?:
                    refused[child] = refusal
                    continue
                case nil:
                    break
                }
                if let app {
                    inUse.append((child, app))
                } else if !listed.isEmpty {
                    leftToDeveloper.append(child)
                } else {
                    removable.append(child)
                }
            }
        }
        let developerFolders = DeveloperCaches.FoldersLeftToDeveloper(
            home: environment.homeDirectory, userCache: environment.userCacheDirectory
        )
        for url in item.urls {
            // Everything in an app's container is that app's, whatever its name.
            let owner = macOSsOwn.container(holding: url).flatMap { running[Naming.normalized($0)] }
            sort(url, leaving: developerFolders.inside(url), owner: owner)
        }
        return (removable, inUse, leftToDeveloper, refused, unreadable, closed)
    }

    /// Maps each name an open app answers to, normalized, to the app's display name. The names are the bundle
    /// identifier, its last part, and the bundle's file name, since many cache and log folders carry the app's
    /// name rather than its identifier (`Firefox`, `Zed`), the application groups its signature claims, whose
    /// group containers it shares with other apps of its maker, and the folders its updater fills while it runs.
    static func namesOfRunningApps(_ running: [RunningCopies.Process]) -> [String: String] {
        var names: [String: String] = [:]
        for process in running {
            let bundle = process.bundleURL?.deletingPathExtension().lastPathComponent
            guard let displayed = name(of: process) else { continue }
            let spellings = [
                process.bundleIdentifier,
                process.bundleIdentifier?.split(separator: ".").last.map(String.init),
                bundle,
            ].compactMap(\.self) + (process.bundleURL.map(AppInspector.applicationGroups) ?? [])
                + updaterFolders(of: process)
            for spelling in spellings where Naming.isSignificant(spelling) {
                names[Naming.normalized(spelling)] = displayed
            }
        }
        return names
    }

    /// The names Peel's own folders go by, from its own process among `running`. Space leaves them alone: Peel runs
    /// whenever Space plans, and they are no other app's to quit.
    static func peelsOwnNames(_ running: [RunningCopies.Process]) -> Set<String> {
        Set(namesOfRunningApps(running.filter { $0.identifier == getpid() }).keys)
    }

    /// The name a plan gives an open app, the one the person knows: Finder's, else its identifier.
    static func name(of process: RunningCopies.Process) -> String? {
        process.bundleURL.map(AppInspector.displayName) ?? process.bundleIdentifier
    }

    /// Those of `apps`, named as a plan names them (`Plan.appsToQuit`), that `running` no longer holds.
    @concurrent
    public static func quit(of apps: [String], running: [RunningCopies.Process]) async -> [String] {
        let open = Set(running.compactMap(name(of:)))
        return apps.filter { !open.contains($0) }
    }

    /// Squirrel's folder, named for the app's identifier, and electron-updater's, named in its `app-update.yml`.
    private static func updaterFolders(of process: RunningCopies.Process) -> [String] {
        let squirrel = process.bundleIdentifier.map { $0 + Squirrel.folderSuffix }
        let electron = process.bundleURL
            .flatMap { ElectronUpdater.configuration(in: $0.appending(path: "Contents", directoryHint: .isDirectory)) }
            .flatMap(ElectronUpdater.downloadsFolder(fromConfiguration:))
        return [squirrel, electron].compactMap(\.self)
    }
}
