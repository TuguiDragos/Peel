import Foundation
internal import PeelPrivileged
import Synchronization

public struct OrphanScanner: Sendable {
    private static let systemPrefixes = [
        "com.apple.", "group.com.apple.", "systemgroup.", "homebrew.", "org.cups.", "org.openssh.", "org.ntp.",
        "org.python.", "org.swift.", "org.llvm.",
    ]

    public let environment: SearchEnvironment
    public let exclusions: Exclusions
    private let isRegisteredApp: @Sendable (String) -> Bool
    private let knownPlaces: @Sendable (String) -> [URL]
    private let isOnAnotherDisk: @Sendable (URL) -> Bool
    /// The apps that come with macOS, which can claim files like any other app. Nil means `AppCatalog.systemApps`.
    private let systemApps: [InstalledApp]?
    private let walk: LeftoverScanner.Measure
    /// The most folders listed per location while looking inside folders no orphan is named after.
    private let nestedFolderLimit: Int
    private let systemExtensions: AppExtensions.SystemExtensionsAnswer
    private let installedByApple: LeftoverScanner.InstalledByApple

    public init(environment: SearchEnvironment = .current, exclusions: Exclusions = .none) {
        self.init(
            environment: environment,
            exclusions: exclusions,
            isRegisteredApp: AppOwnership.launchServicesKnowsApp(withBundleIdentifier:)
        )
    }

    init(
        environment: SearchEnvironment,
        exclusions: Exclusions = .none,
        isRegisteredApp: @escaping @Sendable (String) -> Bool,
        systemApps: [InstalledApp]? = nil,
        walk: @escaping LeftoverScanner.Measure = LeftoverScanner.walk,
        nestedFolderLimit: Int = NestedSearch.folderLimit,
        systemExtensions: @escaping AppExtensions.SystemExtensionsAnswer = AppExtensions.askingMacOS,
        installedByApple: @escaping LeftoverScanner.InstalledByApple = { await PackageReceipts.isInstalledByApple($0) },
        knownPlaces: @escaping @Sendable (String) -> [URL] = AppInspector.applicationURLs(forBundleIdentifier:),
        isOnAnotherDisk: @escaping @Sendable (URL) -> Bool = Disks.isOnAnotherDisk
    ) {
        self.environment = environment
        self.exclusions = exclusions
        self.isRegisteredApp = isRegisteredApp
        self.knownPlaces = knownPlaces
        self.isOnAnotherDisk = isOnAnotherDisk
        self.systemApps = systemApps
        self.walk = walk
        self.nestedFolderLimit = nestedFolderLimit
        self.systemExtensions = systemExtensions
        self.installedByApple = installedByApple
    }

    private var launchdFolders: [URL] {
        environment.locations.filter { $0.kind == .launchAgents || $0.kind == .launchDaemons }.map(\.url)
    }

    /// Finds the items that no app claims, in every location, grouped by identifier.
    ///
    /// `installedApps` must be the complete list: anything it does not claim can be reported as orphaned.
    /// `remembered` holds the apps Peel has seen installed before, so a group can be named after the app that
    /// left it. `running` holds the bundle identifiers of what is running now: a helper or an agent can keep a
    /// folder that no app bundle claims, and while it runs, its group is marked unsure. `owners` are the groups the
    /// person said belong to an app (`OrphanOwners`), left out while that app is installed.
    @concurrent
    public func scan(
        installedApps: [InstalledApp],
        remembered: [RememberedApp] = [],
        running: Set<String> = [],
        owners: [String: String] = [:],
        leftForAnAdministrator records: [LeftForAnAdministrator.Record] = []
    ) async -> OrphanScan {
        let systemApps = if let systemApps { systemApps } else { await AppCatalog.systemApps.value }
        let (installedApps, gone) = Self.split(remembered, installedApps: installedApps)
        let here = Set(installedApps.compactMap { $0.bundleIdentifier?.lowercased() })
        let goneApps = gone.map { $0.bundleIdentifier.lowercased() }
        let knownToMacOS = AppsKnownToMacOS()
        let ownership = AppOwnership(
            installedApps: installedApps + systemApps, goneApps: goneApps,
            isRegisteredApp: { [isRegisteredApp] identifier in
                guard isRegisteredApp(identifier) else { return false }
                knownToMacOS.note(identifier)
                return true
            }
        )
        let jobs = BackgroundItemOwnership(installedApps: installedApps + systemApps).knowingJobs(in: launchdFolders)
        let goneBundles = Dictionary(
            gone.map {
                (
                    PathPattern.comparablePath(of: URL(filePath: $0.lastPath, directoryHint: .isDirectory)),
                    $0.bundleIdentifier
                )
            },
            uniquingKeysWith: { first, _ in first }
        )

        let goneNames = Dictionary(
            gone.map { ($0.name.lowercased(), $0.bundleIdentifier) },
            uniquingKeysWith: { first, _ in first }
        )
        let goneFolders = GoneFolders(gone, installedApps: installedApps, home: environment.homeDirectory)

        let results = await withTaskGroup(of: (location: SearchLocation, result: LocationResult).self) { group in
            let home = environment.homeDirectory.path(percentEncoded: false)
            let root = environment.rootDirectory.path(percentEncoded: false)
            // Safari's web app container is another app's container, which macOS asks about, and is read only for one
            // of its web apps.
            for location in environment.locations where location.kind != .safariWebApps {
                _ = group.addTaskUnlessCancelled { [exclusions, nestedFolderLimit, walk] in
                    // A browser's manifest is an app's only through the program it names (`servesAProgram`).
                    guard location.kind != .nativeMessagingHosts else {
                        let found = await Self.manifests(in: location, home: home, exclusions: exclusions, walk: walk)
                        return (location, found)
                    }
                    return (location, await Self.scan(
                        location, ownership: ownership, jobs: jobs, goneBundles: goneBundles, goneApps: goneApps,
                        goneNames: goneNames, goneFolders: goneFolders, home: home, root: root,
                        exclusions: exclusions, nestedFolderLimit: nestedFolderLimit, walk: walk
                    ))
                }
            }
            return await group.reduce(into: [(location: SearchLocation, result: LocationResult)]()) { $0.append($1) }
        }

        // One location can sit inside another one the walk reaches (the recent documents folder, two levels into
        // Application Support), so a file is listed once, under the location nearer it.
        var found: [(identifier: String, item: OrphanItem)] = []
        var seen: Set<String> = []
        var unreadableLocations: [SearchLocation] = []
        var cutShortLocations: [SearchLocation] = []
        for (_, result) in results.sorted(by: { Self.isNearer($0.location, than: $1.location) }) {
            switch result {
            case .found(let items, let cutShort, let unreadable):
                found += items.filter { seen.insert(PathPattern.comparablePath(of: $0.item.url)).inserted }
                unreadableLocations += unreadable
                if let cutShort { cutShortLocations.append(cutShort) }
            case .unreadable(let location):
                unreadableLocations.append(location)
            }
        }

        let reach = HelperReach(environment: environment)
        let staged = PathPattern.comparablePath(of: environment.rootDirectory.appending(path: "Library/SystemExtensions"))
        let isStaged = { (item: OrphanItem) in
            PathComponents.isPath(PathPattern.comparablePath(of: item.url), inside: staged)
        }
        let extensions = found.contains { isStaged($0.item) } ? await systemExtensions() ?? [] : []
        let leftAlone = Dictionary(
            extensions.compactMap { copy in
                copy.url.flatMap { url in copy.leftAlone.map { (PathPattern.comparablePath(of: url), $0) } }
            },
            uniquingKeysWith: { first, _ in first }
        )
        let installedFor = Dictionary(
            extensions.compactMap { copy in
                copy.url.flatMap { url in copy.installedFor.map { (PathPattern.comparablePath(of: url), $0) } }
            },
            uniquingKeysWith: { first, _ in first }
        )
        let folders = manifestFolders
        let given = Set(owners.filter { here.contains($0.value.lowercased()) }.keys.map { $0.lowercased() })
        let kept = found.compactMap { entry -> (identifier: String, item: OrphanItem, holds: Bool?)? in
            guard !exclusions.excludes(entry.item.url), !exclusions.excludes(bundleIdentifier: entry.identifier),
                  !Self.isInAGroup(entry.identifier, among: given),
                  !Self.servesAProgram(entry.item.url, in: folders)
            else { return nil }
            let holds = exclusions.holdsSomething(entry.item.url)
            return holds == true ? nil : (entry.identifier, entry.item, holds)
        }
        .map { entry in
            var item = entry.item
            if isStaged(item) {
                let path = PathPattern.comparablePath(of: item.url)
                item.heldBack = leftAlone[path] ?? .systemExtension
                item.installedFor = AppExtensions.goneApp(installedFor: installedFor[path])
                return (entry.identifier, item)
            }
            if SignInPlugIns.isOne(item.url, root: environment.rootDirectory) {
                item.heldBack = .signInPlugIn
                return (entry.identifier, item)
            }
            if item.leftAlone == nil, entry.holds == nil {
                item.heldBack = .couldNotLookInside
            }
            return (entry.identifier, Self.holdingBack(item, beyond: reach))
        }
        let teams = Set(installedApps.compactMap(\.teamIdentifier))
        let byPath: (SearchLocation, SearchLocation) -> Bool = {
            $0.url.path(percentEncoded: false) < $1.url.path(percentEncoded: false)
        }
        let (groups, apart) = Self.settingApart(
            Self.group(kept, remembered: gone, installedTeams: teams, running: running)
        )
        let recorded = await recorded(
            records,
            listed: Set(kept.map { ItemKey($0.1.url) }),
            installedApps: installedApps,
            ownership: ownership,
            reach: reach
        )
        return OrphanScan(
            groups: groups,
            unreadableLocations: unreadableLocations.sorted(by: byPath),
            needsFullDiskAccess: unreadableLocations.contains { FullDiskAccess.canList($0.url) == .missing },
            cutShortLocations: cutShortLocations.sorted(by: byPath),
            forAnAdministrator: (Self.claiming(apart, by: records) + recorded)
                .sorted { Self.comesBefore($0.item, $1.item) },
            appsOnOtherDisks: knownToMacOS.identifiers.flatMap(knownPlaces).filter(isOnAnotherDisk)
                .compactMap { AppInspector.inspect($0) }
        )
    }

    /// What the scan set apart, each item an uninstall recorded with that uninstall's apps and claim, unless the claim
    /// was only a hint, which says less than what the scan found itself.
    static func claiming(
        _ apart: [AdministratorItem],
        by records: [LeftForAnAdministrator.Record]
    ) -> [AdministratorItem] {
        let byItem = LeftForAnAdministrator.Record.merged(records)
        return apart.map { entry in
            guard let record = byItem[ItemKey(entry.item.url)], record.confidence >= .likely else { return entry }
            return AdministratorItem(
                item: entry.item,
                apps: record.apps.map(\.name),
                claim: AdministratorItem.Claim(reason: record.reason, confidence: record.confidence)
            )
        }
    }

    /// What uninstalls left for an administrator that the scan didn't list, judged as the scan judges what it finds.
    /// A record is a file any process can write, so only a place an uninstall searches counts, the guard every move
    /// asks judges it too, and what one of Apple's packages installed is never listed.
    private func recorded(
        _ records: [LeftForAnAdministrator.Record],
        listed: Set<ItemKey>,
        installedApps: [InstalledApp],
        ownership: AppOwnership,
        reach: HelperReach
    ) async -> [AdministratorItem] {
        let home = environment.homeDirectory.path(percentEncoded: false)
        let root = environment.rootDirectory.path(percentEncoded: false)
        let installed = Set(installedApps.map { $0.reference.lowercased() })
        let merged = LeftForAnAdministrator.Record.merged(records)
        var seen: Set<ItemKey> = []
        let unlisted = records.compactMap { record -> LeftForAnAdministrator.Record? in
            let item = ItemKey(URL(filePath: record.path))
            guard !listed.contains(item), seen.insert(item).inserted else { return nil }
            return merged[item]
        }
        let places = environment.locations.map { PathPattern.comparablePath(of: $0.url) }
        let searched = unlisted.filter { record in
            let path = PathPattern.comparablePath(of: URL(filePath: record.path))
            return places.contains { PathComponents.isPath(path, inside: $0) }
        }
        let removalGuard = searched.isEmpty ? nil : RemovalGuard(environment: environment, exclusions: exclusions)
        let homePath = PathPattern.comparablePath(of: environment.homeDirectory)
        var candidates: [LeftForAnAdministrator.Record] = []
        for record in searched where !Task.isCancelled {
            let url = URL(filePath: record.path)
            let name = url.lastPathComponent
            let judged = !record.apps.contains { installed.contains($0.reference.lowercased()) }
                && !record.apps.contains { exclusions.excludes(bundleIdentifier: $0.reference) }
                && Self.isAFileAFolderOrALink(url) && !FileAccess.cannotBeRemoved(url)
                && !ProtectedData.refuses(url.path(percentEncoded: false), home: home)
                && !exclusions.excludes(url) && !exclusions.holds(url)
                && !record.apps.contains { app in
                    let identifier = Identifier.isValid(app.reference)
                        ? app.reference : LeftoverMatcher.key(from: name, kind: record.kind)
                    return ownership.isClaimed(fileName: name, kind: record.kind, identifier: identifier)
                }
                && removalGuard?.refusal(of: url) == nil
            guard judged else { continue }
            let isInTheHome = PathComponents.isPath(PathPattern.comparablePath(of: url), atOrInside: homePath)
            if !isInTheHome, await installedByApple(url) { continue }
            candidates.append(record)
        }
        let walked = await candidates.concurrentMap(width: LeftoverScanner.concurrentMeasurements) { [walk] record in
            await walk(URL(filePath: record.path))
        }
        return zip(candidates, walked).compactMap { record, contents in
            let url = URL(filePath: record.path)
            let item = Self.holdingBack(
                Self.item(
                    at: url, kind: record.kind, contents: contents,
                    parent: ParentAccess(url.deletingLastPathComponent()), home: home, root: root
                ),
                beyond: reach
            )
            guard item.isLeftForAnAdministrator else { return nil }
            return AdministratorItem(
                item: item,
                apps: record.apps.map(\.name),
                claim: AdministratorItem.Claim(reason: record.reason, confidence: record.confidence)
            )
        }
    }

    /// The item held back as `beyondTheHelper` when it needs an administrator where the helper may not move it, and
    /// left for an administrator when nothing else held it back.
    static func holdingBack(_ item: OrphanItem, beyond reach: HelperReach) -> OrphanItem {
        guard item.requiresPrivileges, item.leftAlone == nil, reach.isBeyond(item.url) else { return item }
        var item = item
        item.isLeftForAnAdministrator = item.heldBack == nil
        item.heldBack = .beyondTheHelper
        return item
    }

    /// Takes out of `groups` what only an administrator can move, each with the app it was found for. A group Peel is
    /// unsure of keeps its own, since something may still use them, and a group left empty goes.
    static func settingApart(_ groups: [OrphanGroup]) -> (groups: [OrphanGroup], apart: [AdministratorItem]) {
        var apart: [AdministratorItem] = []
        let kept = groups.compactMap { group -> OrphanGroup? in
            guard group.confidence.level != .unsure else { return group }
            let (leaving, staying) = (
                group.items.filter(\.isLeftForAnAdministrator), group.items.filter { !$0.isLeftForAnAdministrator }
            )
            guard !leaving.isEmpty else { return group }
            apart += leaving.map { AdministratorItem(item: $0, apps: [group.title]) }
            guard !staying.isEmpty else { return nil }
            return OrphanGroup(
                identifier: group.identifier,
                items: staying,
                rememberedApp: group.rememberedApp,
                confidence: group.confidence
            )
        }
        return (kept, apart)
    }

    /// The order a list of orphaned items keeps: the largest first, what could not be measured before all, then by
    /// path.
    static func comesBefore(_ one: OrphanItem, _ other: OrphanItem) -> Bool {
        one.size != other.size
            ? SizeTotal([one.size]) > SizeTotal([other.size])
            : one.url.path(percentEncoded: false) < other.url.path(percentEncoded: false)
    }

    private var manifestFolders: Set<String> {
        let manifests = environment.locations.filter { $0.kind == .nativeMessagingHosts }
        return Set(manifests.map { PathPattern.comparablePath(of: $0.url) })
    }

    /// The deeper of two locations first: two as deep never reach the same file, so any fixed order between them does.
    static func isNearer(_ one: SearchLocation, than other: SearchLocation) -> Bool {
        let (path, otherPath) = (one.url.path(percentEncoded: false), other.url.path(percentEncoded: false))
        let (depth, otherDepth) = (PathComponents.of(path).count, PathComponents.of(otherPath).count)
        guard depth == otherDepth else { return depth > otherDepth }
        return (path, one.kind.rawValue) < (otherPath, other.kind.rawValue)
    }

    /// Whether `url` is a manifest in a folder browsers read native messaging manifests from that still serves its
    /// program: one that is there, or that can't be told. Whatever it is named for, it is no orphan then.
    static func servesAProgram(_ url: URL, in folders: Set<String>) -> Bool {
        folders.contains(PathPattern.comparablePath(of: url.deletingLastPathComponent()))
            && !NativeMessagingManifest.startsNothing(at: url)
    }

    /// The manifests in a folder browsers read native messaging manifests from that start nothing, each under its own
    /// name, which is the name of the host it starts.
    private static func manifests(
        in location: SearchLocation,
        home: String,
        exclusions: Exclusions,
        walk: @escaping LeftoverScanner.Measure
    ) async -> LocationResult {
        let entries: [String]
        do {
            entries = try FileManager.default.contentsOfDirectory(atPath: location.url.path(percentEncoded: false))
                .sorted()
        } catch CocoaError.fileReadNoSuchFile {
            return .found([], cutShort: nil, unreadable: [])
        } catch {
            return .unreadable(location)
        }
        let parent = ParentAccess(location.url)
        var found: [(identifier: String, item: OrphanItem)] = []
        for name in entries {
            let url = location.url.appending(path: name)
            let host = (name as NSString).deletingPathExtension
            guard NativeMessagingManifest.startsNothing(at: url), !ProtectedData.isApplesName(host),
                  !FileAccess.cannotBeRemoved(url), !ProtectedData.refuses(url.path(percentEncoded: false), home: home),
                  !exclusions.excludes(url)
            else { continue }
            let contents = await walk(url)
            found.append((host, OrphanItem(
                url: url,
                kind: location.kind,
                size: contents.flatMap { $0.couldNotBeRead ? nil : $0.size },
                modificationDate: contents?.newestChange,
                requiresPrivileges: parent.requiresPrivileges(toRemove: url)
            )))
        }
        return .found(found, cutShort: nil, unreadable: [])
    }

    /// The apps installed now, with those `remembered` holds that are only out of sight, and the remembered apps
    /// that are gone. `remembered` also holds the apps installed now, and only an app that is gone can have left
    /// files behind.
    static func split(
        _ remembered: [RememberedApp], installedApps: [InstalledApp]
    ) -> (installed: [InstalledApp], gone: [RememberedApp]) {
        let listed = Set(installedApps.compactMap { $0.bundleIdentifier?.lowercased() })
        let unlisted = remembered.filter { !listed.contains($0.bundleIdentifier.lowercased()) }
        let outOfSight = unlisted.compactMap { $0.stillInstalled() }
        let here = listed.union(outOfSight.compactMap { $0.bundleIdentifier?.lowercased() })
        return (installedApps + outOfSight, unlisted.filter { !here.contains($0.bundleIdentifier.lowercased()) })
    }

    /// Checks `items` again against `installedApps` and the apps Peel remembers, and returns the ones that are still
    /// orphaned.
    @concurrent
    public func stillOrphaned(
        _ items: [OrphanItem], installedApps: [InstalledApp], remembered: [RememberedApp]
    ) async -> [OrphanItem] {
        let systemApps = if let systemApps { systemApps } else { await AppCatalog.systemApps.value }
        let (installedApps, gone) = Self.split(remembered, installedApps: installedApps)
        let ownership = AppOwnership(
            installedApps: installedApps + systemApps,
            goneApps: gone.map { $0.bundleIdentifier },
            isRegisteredApp: isRegisteredApp
        )
        let jobs = BackgroundItemOwnership(installedApps: installedApps + systemApps).knowingJobs(in: launchdFolders)
        let folders = manifestFolders
        let goneFolders = GoneFolders(gone, installedApps: installedApps, home: environment.homeDirectory)
        var kept: [OrphanItem] = []
        for item in items where !Self.servesAProgram(item.url, in: folders) {
            let isStillOrphaned = if item.kind == .nativeMessagingHosts {
                NativeMessagingManifest.startsNothing(at: item.url)
            } else if item.productFolder != nil {
                Self.goneApp(owningFolder: item.url, kind: item.kind, among: goneFolders, ownership: ownership) != nil
            } else if let app = item.namedAfter {
                await Self.goneApp(
                    named: item.url,
                    kind: item.kind,
                    goneNames: [item.url.lastPathComponent.lowercased(): app],
                    ownership: ownership
                ) == .listed(app)
            } else if case .listed = await Self.orphanIdentifier(
                of: item.url, kind: item.kind, ownership: ownership, jobs: jobs
            ) {
                true
            } else {
                false
            }
            if isStillOrphaned { kept.append(item) }
        }
        return kept
    }

    /// Files that hold a paid license, or a game library worth hundreds of gigabytes, are never reported.
    static func isSensitive(fileName: String) -> Bool {
        let name = fileName.lowercased()
        if name.contains("license") || name.contains("licence") || name.hasSuffix(".lic") { return true }
        return ["steam", "steamlibrary", "epic games", "epicgameslauncher", "battle.net"].contains { name == $0 || name.hasPrefix($0 + ".") }
    }

    static func orphanIdentifier(
        forKey key: String,
        kind: SearchLocation.Kind,
        isDeclared: (String) -> Bool = { _ in false }
    ) -> String? {
        var identifier = key
        if kind == .groupContainers || kind == .applicationScripts, identifier.hasPrefix("group.") {
            identifier.removeFirst("group.".count)
        }
        let lowercased = identifier.lowercased()
        if SafariWebApp.isIdentifier(identifier) { return identifier }
        guard !systemPrefixes.contains(where: lowercased.hasPrefix), !lowercased.contains("com.apple.") else { return nil }

        if Identifier.isReverseDNS(identifier) {
            return identifier
        }
        if kind == .groupContainers, Identifier.teamScoped(identifier) != nil {
            return identifier
        }
        if Identifier.isValid(identifier), isDeclared(identifier) {
            return identifier
        }
        return nil
    }

    static func group(
        _ found: [(identifier: String, item: OrphanItem)],
        remembered: [RememberedApp] = [],
        installedTeams: Set<String> = [],
        running: Set<String> = [],
        now: Date = .now
    ) -> [OrphanGroup] {
        let roots = Set(found.map { groupingKey(for: $0.identifier).lowercased() }).sorted { $0.count < $1.count }
        let grouped = Dictionary(grouping: found) { entry in
            let key = groupingKey(for: entry.identifier).lowercased()
            return roots.first { key == $0 || key.hasPrefix($0 + ".") } ?? key
        }

        return grouped.map { root, entries in
            let identifier = entries.map { groupingKey(for: $0.identifier) }.first { $0.lowercased() == root } ?? root
            let items = entries.map(\.item).sorted(by: comesBefore)
            var group = OrphanGroup(
                identifier: identifier,
                items: items,
                rememberedApp: AppMemory.app(for: identifier, in: remembered)
            )
            group.confidence = OrphanConfidence.judge(group, installedTeams: installedTeams, running: running, now: now)
            return group
        }
        // The groups Peel is surest about come first, the largest first within each level. A big group that the
        // user cannot act on with confidence does not belong at the top of the list.
        .sorted {
            if $0.confidence.level != $1.confidence.level { return $0.confidence.level > $1.confidence.level }
            if $0.total != $1.total { return $0.total > $1.total }
            return $0.identifier < $1.identifier
        }
    }

    /// Whether `identifier` falls in one of `groups`, as `group` gathers them: by its grouping key, the group's own or
    /// one inside it.
    static func isInAGroup(_ identifier: String, among groups: Set<String>) -> Bool {
        let key = groupingKey(for: identifier).lowercased()
        return groups.contains { key == $0 || key.hasPrefix($0 + ".") }
    }

    /// The identifier without a team ID or `group.` in front, when what is left is reverse DNS. For example,
    /// "S8EX82NJP6.group.com.example.app" and "group.com.example.app" both group under "com.example.app".
    static func groupingKey(for identifier: String) -> String {
        var key = Identifier.teamScoped(identifier)?.remainder ?? identifier
        if key.hasPrefix("group.") {
            key.removeFirst("group.".count)
        }
        return Identifier.isReverseDNS(key) ? key : identifier
    }

    /// Whether the folder holds an item that an installed app claims, or nil when it didn't answer in time or macOS
    /// won't list it. Crash reporters and other shared libraries keep one folder per app inside their own, so a folder
    /// named after nobody can still hold an app's files.
    static func holdsFilesOfAnInstalledApp(
        _ url: URL,
        kind: SearchLocation.Kind,
        ownership: AppOwnership
    ) async -> Bool? {
        guard let names = await SlowRead.names(in: url) else { return nil }
        return names.contains { name in
            let key = LeftoverMatcher.key(from: name, kind: kind)
            guard let identifier = orphanIdentifier(forKey: key, kind: kind, isDeclared: ownership.isDeclared)
            else { return false }
            return ownership.isClaimed(fileName: name, kind: kind, identifier: identifier)
        }
    }

    /// Whether the item is a file, a folder, or a link. A socket, a pipe, or a device holds nothing to free, and
    /// a live one belongs to whatever is running.
    static func isAFileAFolderOrALink(_ url: URL) -> Bool {
        var info = stat()
        guard lstat(url.path(percentEncoded: false), &info) == 0 else { return false }
        return [S_IFDIR, S_IFREG, S_IFLNK].contains(info.st_mode & S_IFMT)
    }

    /// Whether a launchd job file still belongs to something. A job belongs to whatever it runs, which is often
    /// no app (Nix, Tailscale), so `BackgroundItemOwnership` decides, as it does for Background Items. A file
    /// that cannot be read is left alone, while a plist that is not a job can still be reported.
    static func isStillAJob(_ url: URL, kind: SearchLocation.Kind, jobs: BackgroundItemOwnership) -> Bool {
        guard kind == .launchAgents || kind == .launchDaemons, url.pathExtension == "plist" else { return false }
        guard let data = BoundedRead.data(at: url) else { return true }
        guard let job = BoundedRead.propertyList(in: data).flatMap(JobDefinition.init) else { return false }
        return !jobs.isOrphan(job)
    }

    /// The app bundle a link leads into, when that bundle is gone. Nil for a link into an app that is still
    /// there or may be, on a disk that isn't connected or where Peel can't look, or into no app at all.
    static func goneApp(behind link: URL) -> URL? {
        guard
            let destination = try? FileManager.default.destinationOfSymbolicLink(
                atPath: link.path(percentEncoded: false)
            )
        else { return nil }
        let components = URL(filePath: destination, relativeTo: link.deletingLastPathComponent())
            .standardizedFileURL.pathComponents
        guard let app = components.firstIndex(where: { $0.hasSuffix(".app") }) else { return nil }
        let bundle = URL(
            filePath: NSString.path(withComponents: Array(components[...app])),
            directoryHint: .isDirectory
        )
        return bundle.isMissing && !bundle.isOnADiskNotConnected ? bundle : nil
    }

    /// What Orphaned Files makes of an item: listed under an identifier, left out, or not known, for a folder that may
    /// hold an installed app's files and that Peel couldn't look into.
    enum Listing: Equatable {
        case listed(String)
        case notListed
        case notKnown
    }

    /// How an item is listed. A link is named for its tool, so it is listed under the app it leads into: the
    /// identifier Peel remembers for that path, or the app's name. With `goneApps`, only an identifier that came with
    /// one of those apps is listed (`cameWithAnAppThatLeft`).
    private static func orphanIdentifier(
        of url: URL,
        kind: SearchLocation.Kind,
        ownership: AppOwnership,
        jobs: BackgroundItemOwnership,
        goneBundles: [String: String] = [:],
        cameWithOneOf goneApps: [String]? = nil
    ) async -> Listing {
        if kind.isForLinks {
            guard let bundle = goneApp(behind: url) else { return .notListed }
            return .listed(
                goneBundles[PathPattern.comparablePath(of: bundle)] ?? bundle.deletingPathExtension().lastPathComponent
            )
        }
        let name = url.lastPathComponent
        guard
            !isSensitive(fileName: name),
            let identifier = (DeclaredIdentifier.nameSaysNothing(of: url, kind: kind)
                ? nil : orphanIdentifier(
                    forKey: LeftoverMatcher.key(from: name, kind: kind), kind: kind, isDeclared: ownership.isDeclared
                ))
                ?? DeclaredIdentifier.of(url, kind: kind).flatMap({
                    orphanIdentifier(forKey: $0, kind: kind, isDeclared: ownership.isDeclared)
                }),
            goneApps.map({ cameWithAnAppThatLeft(identifier, goneApps: $0) }) ?? true,
            !ownership.isClaimed(fileName: name, kind: kind, identifier: identifier),
            !jobs.ownsItem(named: identifier),
            !isStillAJob(url, kind: kind, jobs: jobs)
        else { return .notListed }
        switch await holdsFilesOfAnInstalledApp(url, kind: kind, ownership: ownership) {
        case false?: return .listed(identifier)
        case true?: return .notListed
        case nil: return .notKnown
        }
    }

    /// The gone app whose own product file named `url` for its data, while no installed app has a claim on it.
    static func goneApp(
        owningFolder url: URL,
        kind: SearchLocation.Kind,
        among folders: GoneFolders,
        ownership: AppOwnership
    ) -> (identifier: String, folder: ProductFolder)? {
        guard let named = folders.at(url),
              !ownership.isClaimed(fileName: url.lastPathComponent, kind: kind, identifier: named.identifier)
        else { return nil }
        return named
    }

    /// The places where an app keeps a folder under its own name, such as `Caches/Figma`, and nothing it keeps
    /// there is the person's own work.
    static let namedPlaces: Set<SearchLocation.Kind> = [
        .caches, .logs, .savedApplicationState, .httpStorages, .webKit, .applicationSupport,
    ]

    /// The app that left whose name `url` bears, in one of `namedPlaces`, while no installed app claims that name.
    static func goneApp(
        named url: URL,
        kind: SearchLocation.Kind,
        goneNames: [String: String],
        ownership: AppOwnership
    ) async -> Listing {
        let name = url.lastPathComponent
        guard
            namedPlaces.contains(kind), !isSensitive(fileName: name), !SystemFolders.keeps(name, in: kind),
            let app = goneNames[name.lowercased()],
            !ownership.isClaimed(fileName: name, kind: kind, identifier: app),
            !ownership.anInstalledAppsNameHolds(fileName: name, kind: kind)
        else { return .notListed }
        switch await holdsFilesOfAnInstalledApp(url, kind: kind, ownership: ownership) {
        case false?: return .listed(app)
        case true?: return .notListed
        case nil: return .notKnown
        }
    }

    /// Whether a plug-in or a framework came with an app Peel saw go: its identifier is that app's, extends it, or
    /// is its maker's. An installer can put one in place with no app at all, and its date does not move when it is
    /// used, so nothing else says it was left behind.
    static func cameWithAnAppThatLeft(_ identifier: String, goneApps: [String]) -> Bool {
        let plugIn = identifier.lowercased()
        let maker = Identifier.vendor(of: plugIn)
        return goneApps.contains { app in
            plugIn == app || plugIn.hasPrefix(app + ".") || (maker != nil && maker == Identifier.vendor(of: app))
        }
    }

    private enum LocationResult: Sendable {
        /// `cutShort` is the location itself when the search inside its folders hit the limit, and `unreadable` the
        /// folders inside it that search could not look into.
        case found([(identifier: String, item: OrphanItem)], cutShort: SearchLocation?, unreadable: [SearchLocation])
        case unreadable(SearchLocation)
    }

    /// Something to list, waiting to be measured.
    private struct Candidate {
        let url: URL
        let identifier: String
        var namedAfter: String? = nil
        let parent: ParentAccess
        var folder: ProductFolder? = nil
    }

    private static func scan(
        _ location: SearchLocation,
        ownership: AppOwnership,
        jobs: BackgroundItemOwnership,
        goneBundles: [String: String],
        goneApps: [String],
        goneNames: [String: String],
        goneFolders: GoneFolders,
        home: String,
        root: String,
        exclusions: Exclusions,
        nestedFolderLimit: Int,
        walk: @escaping LeftoverScanner.Measure
    ) async -> LocationResult {
        let entries: [String]
        do {
            // Sorted, because with a limit on how many folders are looked inside, the order decides which ones.
            entries = try FileManager.default.contentsOfDirectory(atPath: location.url.path(percentEncoded: false))
                .sorted()
            ScanCount.current?.add(entries.count)
        } catch CocoaError.fileReadNoSuchFile {
            return .found([], cutShort: nil, unreadable: [])
        } catch {
            return .unreadable(location)
        }

        let parent = ParentAccess(location.url)
        var candidates: [Candidate] = []
        var nobodysFolders: [URL] = []
        var notLookedInto: [URL] = []
        for name in entries where location.considers(fileName: name) {
            guard !Task.isCancelled else { break }
            let url = location.url.appending(path: name)
            guard isAFileAFolderOrALink(url), !FileAccess.cannotBeRemoved(url) else { continue }
            // What the guard refuses outright is never listed, whether an installed app claims it or not.
            guard !ProtectedData.refuses(url.path(percentEncoded: false), home: home) else { continue }
            if let named = goneApp(owningFolder: url, kind: location.kind, among: goneFolders, ownership: ownership) {
                let identifier = named.identifier
                candidates.append(Candidate(url: url, identifier: identifier, parent: parent, folder: named.folder))
                continue
            }
            var namedAfter: String?
            var listing = await orphanIdentifier(
                of: url,
                kind: location.kind,
                ownership: ownership,
                jobs: jobs,
                goneBundles: goneBundles,
                cameWithOneOf: location.kind.isLoadedCode ? goneApps : nil
            )
            if listing == .notListed {
                listing = await goneApp(named: url, kind: location.kind, goneNames: goneNames, ownership: ownership)
                if case .listed(let app) = listing { namedAfter = app }
            }
            switch listing {
            case .listed(let identifier):
                candidates.append(Candidate(url: url, identifier: identifier, namedAfter: namedAfter, parent: parent))
            case .notKnown:
                notLookedInto.append(url)
            case .notListed:
                if NestedSearch.kinds.contains(location.kind), url.isRealFolder, !exclusions.excludes(url) {
                    nobodysFolders.append(url)
                }
            }
        }

        // Inside those folders a dotted name is as often a file's own (a lock, a backup, an editor's extension) as
        // an app's identifier, so only what came with an app Peel saw go is listed there.
        let inside: NestedSearch.Findings<Candidate> = await NestedSearch.walk(
            inside: nobodysFolders,
            of: location.kind,
            limit: nestedFolderLimit
        ) { url, _, parent, canLookInside in
            guard isAFileAFolderOrALink(url), !ProtectedData.refuses(url.path(percentEncoded: false), home: home),
                  !exclusions.excludes(url)
            else { return .pass }
            if let named = goneApp(owningFolder: url, kind: location.kind, among: goneFolders, ownership: ownership) {
                return .take(Candidate(url: url, identifier: named.identifier, parent: parent, folder: named.folder))
            }
            switch await orphanIdentifier(
                of: url, kind: location.kind, ownership: ownership, jobs: jobs, cameWithOneOf: goneApps
            ) {
            case .listed(let identifier): return .take(Candidate(url: url, identifier: identifier, parent: parent))
            case .notKnown: return .notKnown
            case .notListed: return canLookInside && url.isRealFolder ? .lookInside : .pass
            }
        }
        candidates += inside.found

        // A few walks at a time, so a few folders that never answer do not each hold the location for a whole budget.
        let walked = await candidates.map(\.url).concurrentMap(width: LeftoverScanner.concurrentMeasurements) {
            await walk($0)
        }
        let found = zip(candidates, walked).map { candidate, contents in
            (
                identifier: candidate.identifier,
                item: item(
                    at: candidate.url, kind: location.kind, contents: contents, parent: candidate.parent, home: home,
                    root: root, namedAfter: candidate.namedAfter, folder: candidate.folder
                )
            )
        }
        return .found(
            found,
            cutShort: inside.wasCutShort ? location : nil,
            unreadable: (notLookedInto + inside.unreadable).map { SearchLocation(kind: location.kind, url: $0) }
        )
    }

    /// The orphaned item at `url`, with its size and newest write from its walk, held back for what it holds, where
    /// it is, and what its walk saw.
    private static func item(
        at url: URL,
        kind: SearchLocation.Kind,
        contents: FolderContents?,
        parent: ParentAccess,
        home: String,
        root: String,
        namedAfter: String? = nil,
        folder: ProductFolder? = nil
    ) -> OrphanItem {
        // The item's own date changes when something is taken out of it, but not when a file inside is
        // rewritten in place, so the newest date inside comes from the walk.
        let own = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        let path = url.path(percentEncoded: false)
        let requiresPrivileges = parent.requiresPrivileges(toRemove: url)
        let wallet = ProtectedData.holdsABrowserWallet(path)
        let library = ProtectedData.holdsALibrary(path)
        let work = ProtectedData.holdsWorkKeptInACache(path)
        let heldBack: HoldBack? = if kind == .containers, ProtectedData.holdsAContainersDocuments(path) {
            .holdsDocuments
        } else if ProtectedData.holds(path, home: home) || wallet == .found {
            .holdsKeys
        } else if library == .found {
            .holdsALibrary
        } else if work == .found {
            .holdsWorkKeptInACache
        } else if !requiresPrivileges, [wallet, library, work].contains(.notKnown) {
            .couldNotLookInside
        } else if let keptOnlyHere = KeptOnlyHere.reason(for: path, home: home, root: root) {
            keptOnlyHere
        } else if folder?.holdsWork(at: url) == true {
            .holdsWorkMadeWithTheApp
        } else if kind == .logs, CrashReport.isOne(url) {
            .crashReport
        } else {
            // `/Users/Shared` belongs to every account on the Mac, and the other accounts' apps are not known here.
            HoldBack.seen(in: contents) ?? contents.flatMap(KeptOnlyHere.reason(seenIn:))
                ?? (kind == .sharedFolder ? .sharedWithEveryone : nil) ?? (namedAfter != nil ? .namedLikeTheApp : nil)
        }
        return OrphanItem(
            url: url,
            kind: kind,
            size: contents.flatMap { $0.couldNotBeRead ? nil : $0.size },
            modificationDate: [own, contents?.newestChange].compactMap(\.self).max(),
            requiresPrivileges: requiresPrivileges,
            heldBack: heldBack,
            namedAfter: namedAfter,
            holdsDamagedSettings: kind == .preferences && PreferenceFile.isDamaged(url),
            productFolder: folder
        )
    }
}

/// The folders the product files of apps Peel saw go named for their data, by where they are. A folder an installed
/// app's product file names too is left out.
struct GoneFolders: Sendable {
    private let byPath: [String: (identifier: String, folder: ProductFolder)]
    private let names: Set<String>

    init(_ gone: [RememberedApp], installedApps: [InstalledApp], home: URL) {
        let named = Set(installedApps.flatMap(\.productFolders).map { $0.path.lowercased() })
        var byPath: [String: (identifier: String, folder: ProductFolder)] = [:]
        for app in gone {
            for folder in app.productFolders ?? []
            where ProductFolders.believes(folder) && !named.contains(folder.path.lowercased()) {
                let path = PathPattern.comparablePath(of: home.appending(path: folder.path)).lowercased()
                byPath[path] = byPath[path] ?? (app.bundleIdentifier, folder)
            }
        }
        self.byPath = byPath
        names = Set(byPath.keys.compactMap { PathComponents.of($0).last })
    }

    /// The gone app whose folder `url` is, while it holds what that app writes there.
    func at(_ url: URL) -> (identifier: String, folder: ProductFolder)? {
        guard !names.isEmpty, names.contains(url.lastPathComponent.lowercased()),
              let named = byPath[PathPattern.comparablePath(of: url).lowercased()], named.folder.holdsProof(at: url)
        else { return nil }
        return named
    }
}

/// The apps macOS knows, by identifier, that claimed something during one scan.
private final class AppsKnownToMacOS: Sendable {
    private let claimed = Mutex<Set<String>>([])

    var identifiers: [String] { claimed.withLock { $0.sorted() } }

    func note(_ identifier: String) {
        _ = claimed.withLock { $0.insert(identifier) }
    }
}
