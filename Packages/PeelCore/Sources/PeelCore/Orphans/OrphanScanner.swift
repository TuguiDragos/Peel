import Foundation
internal import PeelPrivileged

public struct OrphanScanner: Sendable {
    private static let systemPrefixes = [
        "com.apple.", "group.com.apple.", "systemgroup.", "homebrew.", "org.cups.", "org.openssh.", "org.ntp.",
        "org.python.", "org.swift.", "org.llvm.",
    ]

    public let environment: SearchEnvironment
    public let exclusions: Exclusions
    private let isRegisteredApp: @Sendable (String) -> Bool
    /// The apps that come with macOS, which can claim files like any other app. Nil means `AppCatalog.systemApps`.
    private let systemApps: [InstalledApp]?
    private let walk: LeftoverScanner.Measure
    /// The most folders listed per location while looking inside folders no orphan is named after.
    private let nestedFolderLimit: Int

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
        nestedFolderLimit: Int = NestedSearch.folderLimit
    ) {
        self.environment = environment
        self.exclusions = exclusions
        self.isRegisteredApp = isRegisteredApp
        self.systemApps = systemApps
        self.walk = walk
        self.nestedFolderLimit = nestedFolderLimit
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
        owners: [String: String] = [:]
    ) async -> OrphanScan {
        let systemApps = if let systemApps { systemApps } else { await AppCatalog.systemApps.value }
        // `remembered` also holds the apps installed now, and only an app that is gone can have left files behind.
        let listed = Set(installedApps.map { $0.bundleIdentifier.lowercased() })
        let unlisted = remembered.filter { !listed.contains($0.bundleIdentifier.lowercased()) }
        let outOfSight = unlisted.compactMap { $0.stillInstalled() }
        let installedApps = installedApps + outOfSight
        let here = listed.union(outOfSight.map { $0.bundleIdentifier.lowercased() })
        let gone = unlisted.filter { !here.contains($0.bundleIdentifier.lowercased()) }
        let ownership = AppOwnership(installedApps: installedApps + systemApps, isRegisteredApp: isRegisteredApp)
        let jobs = BackgroundItemOwnership(installedApps: installedApps + systemApps)
        let goneBundles = Dictionary(
            gone.map {
                (
                    PathPattern.comparablePath(of: URL(filePath: $0.lastPath, directoryHint: .isDirectory)),
                    $0.bundleIdentifier
                )
            },
            uniquingKeysWith: { first, _ in first }
        )

        let goneApps = gone.map { $0.bundleIdentifier.lowercased() }
        let goneNames = Dictionary(
            gone.map { ($0.name.lowercased(), $0.bundleIdentifier) },
            uniquingKeysWith: { first, _ in first }
        )

        let results = await withTaskGroup(of: LocationResult.self) { group in
            let home = environment.homeDirectory.path(percentEncoded: false)
            // A browser's manifest is an app's only through the program it names, which an uninstall reads. Here one
            // is still found by the identifier it is named for, inside Application Support. Safari's web app
            // container is another app's container, which macOS asks about, and is read only for one of its web apps.
            let skipped: Set<SearchLocation.Kind> = [.nativeMessagingHosts, .safariWebApps]
            for location in environment.locations where !skipped.contains(location.kind) {
                _ = group.addTaskUnlessCancelled { [exclusions, nestedFolderLimit, walk] in
                    await Self.scan(
                        location, ownership: ownership, jobs: jobs, goneBundles: goneBundles, goneApps: goneApps,
                        goneNames: goneNames, home: home, exclusions: exclusions, nestedFolderLimit: nestedFolderLimit,
                        walk: walk
                    )
                }
            }
            return await group.reduce(into: [LocationResult]()) { $0.append($1) }
        }

        var found: [(identifier: String, item: OrphanItem)] = []
        var unreadableLocations: [SearchLocation] = []
        var cutShortLocations: [SearchLocation] = []
        for result in results {
            switch result {
            case .found(let items, let cutShort, let unreadable):
                found += items
                unreadableLocations += unreadable
                if let cutShort { cutShortLocations.append(cutShort) }
            case .unreadable(let location):
                unreadableLocations.append(location)
            }
        }

        let reach = HelperReach(environment: environment)
        let kept = found.filter {
            !exclusions.excludes($0.item.url) && !exclusions.holds($0.item.url)
                && !exclusions.excludes(bundleIdentifier: $0.identifier)
                && !(owners[$0.identifier.lowercased()].map { here.contains($0.lowercased()) } ?? false)
        }
        .map { entry in
            guard entry.item.requiresPrivileges, entry.item.leftAlone == nil, reach.isBeyond(entry.item.url) else {
                return entry
            }
            var item = entry.item
            item.heldBack = .beyondTheHelper
            return (entry.identifier, item)
        }
        let teams = Set(installedApps.compactMap(\.teamIdentifier))
        let byPath: (SearchLocation, SearchLocation) -> Bool = {
            $0.url.path(percentEncoded: false) < $1.url.path(percentEncoded: false)
        }
        return OrphanScan(
            groups: Self.group(kept, remembered: gone, installedTeams: teams, running: running),
            unreadableLocations: unreadableLocations.sorted(by: byPath),
            needsFullDiskAccess: unreadableLocations.contains { FullDiskAccess.canList($0.url) == .missing },
            cutShortLocations: cutShortLocations.sorted(by: byPath)
        )
    }

    /// Checks `items` again against `installedApps` and returns the ones that are still orphaned.
    @concurrent
    public func stillOrphaned(_ items: [OrphanItem], installedApps: [InstalledApp]) async -> [OrphanItem] {
        let systemApps = if let systemApps { systemApps } else { await AppCatalog.systemApps.value }
        let ownership = AppOwnership(installedApps: installedApps + systemApps, isRegisteredApp: isRegisteredApp)
        let jobs = BackgroundItemOwnership(installedApps: installedApps + systemApps)
        var kept: [OrphanItem] = []
        for item in items {
            let isStillOrphaned = if let app = item.namedAfter {
                await Self.goneApp(
                    named: item.url,
                    kind: item.kind,
                    goneNames: [item.url.lastPathComponent.lowercased(): app],
                    ownership: ownership
                ) != nil
            } else {
                await Self.orphanIdentifier(of: item.url, kind: item.kind, ownership: ownership, jobs: jobs) != nil
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

    static func orphanIdentifier(forKey key: String, kind: SearchLocation.Kind) -> String? {
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
            let items = entries.map(\.item).sorted {
                $0.size != $1.size
                    ? SizeTotal([$0.size]) > SizeTotal([$1.size])
                    : $0.url.path(percentEncoded: false) < $1.url.path(percentEncoded: false)
            }
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

    /// The identifier without a team ID or `group.` in front, when what is left is reverse DNS. For example,
    /// "S8EX82NJP6.group.com.example.app" and "group.com.example.app" both group under "com.example.app".
    static func groupingKey(for identifier: String) -> String {
        var key = Identifier.teamScoped(identifier)?.remainder ?? identifier
        if key.hasPrefix("group.") {
            key.removeFirst("group.".count)
        }
        return Identifier.isReverseDNS(key) ? key : identifier
    }

    /// Whether the folder holds an item that an installed app claims. Crash reporters and other shared libraries
    /// keep one folder per app inside their own, so a folder named after nobody can still hold an app's files.
    /// A folder that did not answer in time, or that macOS will not list, counts as holding one, so it is never
    /// reported as nobody's.
    static func holdsFilesOfAnInstalledApp(
        _ url: URL,
        kind: SearchLocation.Kind,
        ownership: AppOwnership
    ) async -> Bool {
        guard let names = await SlowRead.names(in: url) else { return true }
        return names.contains { name in
            let key = LeftoverMatcher.key(from: name, kind: kind)
            guard let identifier = orphanIdentifier(forKey: key, kind: kind) else { return false }
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
    /// there, or into no app at all.
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
        return FileManager.default.fileExists(atPath: bundle.path(percentEncoded: false)) ? nil : bundle
    }

    /// The identifier an item is listed under, or nil when it must not be listed. A link is named for its tool,
    /// so it is listed under the app it leads into: the identifier Peel remembers for that path, or the app's name.
    /// With `goneApps`, only an identifier that came with one of those apps is listed (`cameWithAnAppThatLeft`).
    private static func orphanIdentifier(
        of url: URL,
        kind: SearchLocation.Kind,
        ownership: AppOwnership,
        jobs: BackgroundItemOwnership,
        goneBundles: [String: String] = [:],
        cameWithOneOf goneApps: [String]? = nil
    ) async -> String? {
        if kind.isForLinks {
            guard let bundle = goneApp(behind: url) else { return nil }
            return goneBundles[PathPattern.comparablePath(of: bundle)]
                ?? bundle.deletingPathExtension().lastPathComponent
        }
        let name = url.lastPathComponent
        guard
            !isSensitive(fileName: name),
            let identifier = (DeclaredIdentifier.nameSaysNothing(of: url, kind: kind)
                ? nil : orphanIdentifier(forKey: LeftoverMatcher.key(from: name, kind: kind), kind: kind))
                ?? DeclaredIdentifier.of(url, kind: kind).flatMap({ orphanIdentifier(forKey: $0, kind: kind) }),
            goneApps.map({ cameWithAnAppThatLeft(identifier, goneApps: $0) }) ?? true,
            !ownership.isClaimed(fileName: name, kind: kind, identifier: identifier),
            await !holdsFilesOfAnInstalledApp(url, kind: kind, ownership: ownership),
            !isStillAJob(url, kind: kind, jobs: jobs)
        else { return nil }
        return identifier
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
    ) async -> String? {
        let name = url.lastPathComponent
        guard
            namedPlaces.contains(kind), !isSensitive(fileName: name),
            let app = goneNames[name.lowercased()],
            !ownership.isClaimed(fileName: name, kind: kind, identifier: app)
        else { return nil }
        return await holdsFilesOfAnInstalledApp(url, kind: kind, ownership: ownership) ? nil : app
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
        let namedAfter: String?
        let parent: ParentAccess
    }

    private static func scan(
        _ location: SearchLocation,
        ownership: AppOwnership,
        jobs: BackgroundItemOwnership,
        goneBundles: [String: String],
        goneApps: [String],
        goneNames: [String: String],
        home: String,
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
        for name in entries where location.considers(fileName: name) {
            guard !Task.isCancelled else { break }
            let url = location.url.appending(path: name)
            guard isAFileAFolderOrALink(url), !FileAccess.cannotBeRemoved(url) else { continue }
            // What the guard refuses outright is never listed, whether an installed app claims it or not.
            guard !ProtectedData.refuses(url.path(percentEncoded: false), home: home) else { continue }
            var namedAfter: String?
            var identifier = await orphanIdentifier(
                of: url,
                kind: location.kind,
                ownership: ownership,
                jobs: jobs,
                goneBundles: goneBundles,
                cameWithOneOf: location.kind.isLoadedCode ? goneApps : nil
            )
            if identifier == nil {
                namedAfter = await goneApp(named: url, kind: location.kind, goneNames: goneNames, ownership: ownership)
                identifier = namedAfter
            }
            if let identifier {
                candidates.append(Candidate(url: url, identifier: identifier, namedAfter: namedAfter, parent: parent))
            } else if NestedSearch.kinds.contains(location.kind), url.isRealFolder, !exclusions.excludes(url) {
                nobodysFolders.append(url)
            }
        }

        // Inside those folders a dotted name is as often a file's own (a lock, a backup, an editor's extension) as
        // an app's identifier, so only what came with an app Peel saw go is listed there.
        let inside: NestedSearch.Findings<Candidate> = await NestedSearch.walk(
            inside: nobodysFolders,
            limit: nestedFolderLimit
        ) { url, _, parent, canLookInside in
            guard isAFileAFolderOrALink(url), !ProtectedData.refuses(url.path(percentEncoded: false), home: home),
                  !exclusions.excludes(url)
            else { return .pass }
            if let identifier = await orphanIdentifier(
                of: url, kind: location.kind, ownership: ownership, jobs: jobs, cameWithOneOf: goneApps
            ) {
                return .take(Candidate(url: url, identifier: identifier, namedAfter: nil, parent: parent))
            }
            return canLookInside && url.isRealFolder ? .lookInside : .pass
        }
        candidates += inside.found

        // A few walks at a time, so a few folders that never answer do not each hold the location for a whole budget.
        let walked = await candidates.map(\.url).concurrentMap(width: LeftoverScanner.concurrentMeasurements) {
            await walk($0)
        }
        var found: [(identifier: String, item: OrphanItem)] = []
        for (candidate, contents) in zip(candidates, walked) {
            let url = candidate.url
            // The item's own date changes when something is taken out of it, but not when a file inside is
            // rewritten in place, so the newest date inside comes from the walk.
            let own = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            let path = url.path(percentEncoded: false)
            let heldBack: HoldBack? = if location.kind == .containers, ProtectedData.holdsAContainersDocuments(path) {
                .holdsDocuments
            } else if ProtectedData.holds(path, home: home) || ProtectedData.holdsABrowserWallet(path) {
                .holdsKeys
            } else if ProtectedData.holdsALibrary(path) {
                .holdsALibrary
            } else if ProtectedData.holdsWorkKeptInACache(path) {
                .holdsWorkKeptInACache
            } else if let keptOnlyHere = KeptOnlyHere.reason(for: path, home: home) {
                keptOnlyHere
            } else if location.kind == .logs, CrashReport.isOne(url) {
                .crashReport
            } else {
                // `/Users/Shared` belongs to every account on the Mac, and the other accounts' apps are not known here.
                HoldBack.seen(in: contents) ?? (location.kind == .sharedFolder ? .sharedWithEveryone : nil)
                    ?? (candidate.namedAfter != nil ? .namedLikeTheApp : nil)
            }
            let item = OrphanItem(
                url: url,
                kind: location.kind,
                size: contents.flatMap { $0.couldNotBeRead ? nil : $0.size },
                modificationDate: [own, contents?.newestChange].compactMap(\.self).max(),
                requiresPrivileges: candidate.parent.requiresPrivileges(toRemove: url),
                heldBack: heldBack,
                namedAfter: candidate.namedAfter,
                holdsDamagedSettings: location.kind == .preferences && PreferenceFile.isDamaged(url)
            )
            found.append((candidate.identifier, item))
        }
        return .found(
            found,
            cutShort: inside.wasCutShort ? location : nil,
            unreadable: inside.unreadable.map { SearchLocation(kind: location.kind, url: $0) }
        )
    }
}
