import Foundation
internal import PeelPrivileged

public struct LeftoverScanner: Sendable {
    typealias Measure = @Sendable (URL) async -> FolderContents?
    /// Whether the guard refuses a path outright, whatever the rest of the scan makes of it.
    typealias Refuses = @Sendable (_ path: String, _ home: String) -> Bool

    public let environment: SearchEnvironment
    public let exclusions: Exclusions
    private let measure: Measure
    private let refuses: Refuses
    private let registeredApp: LeftoverMatcher.RegisteredApp
    /// The most folders listed per location while searching inside folders the app does not claim. The default
    /// is far more than a busy Application Support or Caches folder needs, and each listing is cheap.
    private let nestedFolderLimit: Int

    public init(environment: SearchEnvironment = .current, exclusions: Exclusions = .none) {
        self.init(environment: environment, exclusions: exclusions, measure: Self.walk, registeredApp: AppInspector.applicationURL(forBundleIdentifier:))
    }

    static let walk: Measure = { await FileSize.contents(of: $0) }

    /// For tests, which say how each folder answers and can count what the guard is asked. They leave out Launch
    /// Services, whose answers depend on what is installed on the Mac running them.
    init(
        environment: SearchEnvironment,
        exclusions: Exclusions = .none,
        measure: @escaping Measure,
        refuses: @escaping Refuses = { ProtectedData.refuses($0, home: $1) },
        registeredApp: @escaping LeftoverMatcher.RegisteredApp = { _ in nil },
        nestedFolderLimit: Int = 5_000
    ) {
        self.environment = environment
        self.exclusions = exclusions
        self.measure = measure
        self.refuses = refuses
        self.registeredApp = registeredApp
        self.nestedFolderLimit = nestedFolderLimit
    }

    /// Finds the files `app` keeps outside its bundle. `installedApps` should hold every app on the Mac, so files
    /// other apps use are marked as shared. The apps macOS ships are added as rivals too: Apple keeps folders
    /// under their names (`Application Support/Music`) that an app of the same name would otherwise get outright.
    @concurrent
    public func scan(_ app: InstalledApp, installedApps: [InstalledApp]) async -> LeftoverScan {
        let systemApps = await AppCatalog.systemApps.value
        let matcher = LeftoverMatcher(app: app, installedApps: installedApps + systemApps, registeredApp: registeredApp)

        let results = await withTaskGroup(of: (location: SearchLocation, result: LocationResult).self) { group in
            for location in environment.locations {
                let home = environment.homeDirectory.path(percentEncoded: false)
                let bundle = PathPattern.comparablePath(of: app.url)
                _ = group.addTaskUnlessCancelled { [measure, refuses, nestedFolderLimit] in
                    (location, await Self.scan(
                        location, matcher: matcher, home: home, bundle: bundle, measure: measure, refuses: refuses,
                        nestedFolderLimit: nestedFolderLimit
                    ))
                }
            }
            return await group.reduce(into: [(location: SearchLocation, result: LocationResult)]()) { $0.append($1) }
        }

        var found: [(location: SearchLocation, leftovers: [Leftover])] = []
        var unreadableLocations: [SearchLocation] = []
        var cutShortLocations: [SearchLocation] = []
        for (location, result) in results {
            switch result {
            case .found(let leftovers, let cutShort):
                found.append((location, leftovers))
                if let cutShort { cutShortLocations.append(cutShort) }
            case .unreadable(let location):
                unreadableLocations.append(location)
            }
        }
        let leftovers = Self.merged(found)

        return LeftoverScan(
            leftovers: exclusions.keeping(leftovers, url: \.url)
                .map { exclusions.holds($0.url) ? $0.heldBack(.holdsAnExclusion) : $0 }
                .sorted(by: Leftover.comesBefore),
            unreadableLocations: unreadableLocations.sorted { $0.url.path(percentEncoded: false) < $1.url.path(percentEncoded: false) },
            cutShortLocations: cutShortLocations.sorted { $0.url.path(percentEncoded: false) < $1.url.path(percentEncoded: false) }
        )
    }

    /// One location can sit inside another (the recent documents folder is two levels inside Application
    /// Support, which is looked into that deep), so a file can be reached two ways. It is listed once, under the
    /// stronger claim: a `Leftover` is known by its path. Between claims of equal strength the location nearer the
    /// file wins, so the row does not depend on which search ended first.
    static func merged(_ found: [(location: SearchLocation, leftovers: [Leftover])]) -> [Leftover] {
        func depth(_ location: SearchLocation) -> Int {
            PathComponents.of(location.url.path(percentEncoded: false)).count
        }
        let nearestFirst = found.sorted { one, other in
            guard depth(one.location) == depth(other.location) else { return depth(one.location) > depth(other.location) }
            // Two locations as deep never reach the same file; any fixed order will do.
            return (one.location.url.path(percentEncoded: false), one.location.kind.rawValue)
                < (other.location.url.path(percentEncoded: false), other.location.kind.rawValue)
        }
        var byPath: [String: Leftover] = [:]
        for (_, leftovers) in nearestFirst {
            for leftover in leftovers {
                let path = PathPattern.comparablePath(of: leftover.url)
                if let known = byPath[path], known.match.confidence >= leftover.match.confidence { continue }
                byPath[path] = leftover
            }
        }
        return Array(byPath.values)
    }

    private enum LocationResult: Sendable {
        /// `cutShort` is the location itself when the search inside its folders hit the limit.
        case found([Leftover], cutShort: SearchLocation?)
        case unreadable(SearchLocation)
    }

    /// Kinds of location where an app's files can sit inside a folder that belongs to somebody else: a crash
    /// reporter's data folder, macOS's help cache, or a vendor's folder shared by several apps, such as
    /// `VST3/Native Instruments` or `/Users/Shared/<Vendor>`. In `/Users/Shared`, everything found is held back.
    private static let nestedKinds: Set<SearchLocation.Kind> = [
        .applicationSupport, .caches, .logs, .hiddenHomeFiles, .plugIns, .sharedFolder,
    ]
    private static let nestedDepth = 2

    /// Kinds of location that belong to macOS or to the user, where a match on the app's name alone is a guess:
    /// there is a real app called Developer, and `~/Library/Developer` is Xcode's.
    private static let namedGroundOfSomebodyElse: Set<SearchLocation.Kind> = [.hiddenHomeFiles, .library, .homeFolder]

    private static func scan(
        _ location: SearchLocation,
        matcher: LeftoverMatcher,
        home: String,
        bundle: String,
        measure: Measure,
        refuses: Refuses,
        nestedFolderLimit: Int
    ) async -> LocationResult {
        let entries: [String]
        do {
            // Sorted, because Apple documents the order of a listing as undefined, and with a limit on how many
            // folders are looked into, the order decides which ones.
            entries = try FileManager.default.contentsOfDirectory(atPath: location.url.path(percentEncoded: false)).sorted()
            ScanCount.current?.add(entries.count)
        } catch CocoaError.fileReadNoSuchFile {
            return .found([], cutShort: nil)
        } catch {
            return .unreadable(location)
        }

        let parent = ParentAccess(location.url)
        var leftovers: [Leftover] = []
        var nobodysFolders: [(url: URL, isAnotherApps: Bool)] = []

        // The guard reads every spelling of a path from the disk, so it is asked only about what the scan would
        // take or walk into, and what it refuses is left out of both.
        for name in entries where location.kind.considers(fileName: name) {
            // A canceled scan stops here, since nobody will read what it finds.
            guard !Task.isCancelled else { break }
            let url = location.url.appending(path: name)
            let path = url.path(percentEncoded: false)
            if let match = claim(name, at: url, kind: location.kind, matcher: matcher, bundle: bundle), !isSharedWithTheWholeMac(url, home: home) {
                guard !refuses(path, home) else { continue }
                leftovers.append(await leftover(at: url, kind: location.kind, match: match, parent: parent, home: home, measure: measure))
            } else if nestedKinds.contains(location.kind), url.isRealFolder, !refuses(path, home) {
                // Not this app's. Whether it is somebody else's decides what a name inside it is worth.
                nobodysFolders.append((url, isSomebodyElses(name, kind: location.kind, matcher: matcher)))
            }
        }

        let inside = await nested(
            in: nobodysFolders, kind: location.kind, matcher: matcher, home: home, measure: measure, refuses: refuses,
            limit: nestedFolderLimit
        )
        return .found(leftovers + inside.found, cutShort: inside.wasCutShort ? location : nil)
    }

    /// Looks up to two levels inside the folders not taken as the app's. Only a match strong enough to name the
    /// app on its own (`likely` or better) is taken, because everything else in there is somebody else's.
    private static func nested(
        in folders: [(url: URL, isAnotherApps: Bool)],
        kind: SearchLocation.Kind,
        matcher: LeftoverMatcher,
        home: String,
        measure: Measure,
        refuses: Refuses,
        limit: Int
    ) async -> (found: [Leftover], wasCutShort: Bool) {
        var found: [Leftover] = []
        var pending = folders
        var visited = 0

        for depth in 0..<nestedDepth {
            var deeper: [(url: URL, isAnotherApps: Bool)] = []
            for (folder, isAnotherApps) in pending {
                guard !Task.isCancelled else { return (found, false) }
                guard visited < limit else { return (found, true) }
                visited += 1
                guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false)).sorted() else { continue }
                ScanCount.current?.add(names.count)

                let parent = ParentAccess(folder)
                for name in names {
                    let url = folder.appending(path: name)
                    let path = url.path(percentEncoded: false)
                    if let match = matcher.match(fileName: name, kind: kind), match.confidence >= .likely,
                       !isSharedWithTheWholeMac(url, home: home) {
                        guard !refuses(path, home) else { continue }
                        found.append(await leftover(at: url, kind: kind, match: match, parent: parent, home: home, isInsideAnotherAppsFolder: isAnotherApps, measure: measure))
                    } else if depth + 1 < nestedDepth, url.isRealFolder, !refuses(path, home) {
                        deeper.append((url, isAnotherApps || isSomebodyElses(name, kind: kind, matcher: matcher)))
                    }
                }
            }
            pending = deeper
        }
        return (found, false)
    }

    /// Builds a leftover: measures it and decides whether to hold it back. The scan, cask paths, and installer
    /// receipts all come through here, so the same rules apply to every leftover.
    static func leftover(
        at url: URL,
        kind: SearchLocation.Kind,
        match: LeftoverMatch,
        parent: ParentAccess,
        home: String,
        isInsideAnotherAppsFolder: Bool = false,
        measure: Measure = LeftoverScanner.walk
    ) async -> Leftover {
        // The walk that measures the folder also reports whether it saw a repository or a wallet, so neither
        // check costs extra reading. A repository means the folder holds more than the app's state, such as work
        // that was never pushed, and holding it back costs a checkmark, not a file.
        // A folder that did not answer in time is unknown, not empty: it may hold a repository, and the largest
        // folders are the ones that run out of time.
        let contents = await measure(url)
        // What the guard will refuse comes first, whatever the walk saw. A folder macOS refuses to open would read
        // as empty, and an empty folder of the app's own would be selected. From macOS 27, another team's container
        // is refused outright rather than prompted for.
        let heldBack: HoldBack? = if ProtectedData.holds(url.path(percentEncoded: false), home: home)
            || ProtectedData.holdsABrowserWallet(url.path(percentEncoded: false)) {
            .holdsKeys
        } else if kind == .containers, ProtectedData.holdsAContainersDocuments(url.path(percentEncoded: false)) {
            .holdsDocuments
        } else if ProtectedData.holdsALibrary(url.path(percentEncoded: false)) {
            .holdsALibrary
        } else if contents?.couldNotBeRead == true {
            .couldNotBeRead
        } else if let contents {
            heldBack(match, in: kind, contents: contents, isInsideAnotherAppsFolder: isInsideAnotherAppsFolder)
        } else {
            .notMeasured
        }
        return Leftover(
            url: url,
            kind: kind,
            match: heldBack.map(match.forReview) ?? match,
            size: contents?.size ?? 0,
            isMeasured: contents.map { !$0.couldNotBeRead } ?? false,
            requiresPrivileges: parent.requiresPrivileges(toRemove: url)
        )
    }

    /// The reason to show a leftover but leave it unselected, or nil. The scan never lists what the guard refuses
    /// outright (`ProtectedData.refuses`), such as mail, keys, and iCloud Drive.
    ///
    /// In the home folder and at the top of a Library, the app's name alone is weak evidence: a hidden `~/.jotter`
    /// can belong to a command-line tool of the same name rather than to the Jotter app, and hold work that exists
    /// nowhere else. This is decided here and not in the matcher, because `nested(in:)` takes an item only on strong
    /// evidence, and weaker evidence would drop items such as `~/.config/zed` from the scan instead of showing them
    /// unselected.
    private static func heldBack(
        _ match: LeftoverMatch,
        in kind: SearchLocation.Kind,
        contents: FolderContents,
        isInsideAnotherAppsFolder: Bool
    ) -> HoldBack? {
        // A wallet comes first: a cask's `zap` can name a coin app's whole data folder, which is where its keys
        // are. Holding it back costs a checkmark, and the row says what is inside.
        if contents.holdsWallet { return .holdsAWallet }
        if contents.holdsRepository { return .holdsRepository }
        if kind == .sharedFolder { return .sharedWithEveryone }
        if Self.namedGroundOfSomebodyElse.contains(kind), match.restsOnAName { return .namedLikeTheApp }
        // An identifier names the app wherever it sits. Its name, inside somebody else's folder, does not.
        if isInsideAnotherAppsFolder, match.restsOnAName { return .insideAnotherAppsFolder }
        return nil
    }

    /// This app's claim on an item, from its name and then from what it holds. A plug-in is named for what it
    /// does, and a launchd job by whoever wrote it, so their names do not say whose they are.
    private static func claim(
        _ name: String,
        at url: URL,
        kind: SearchLocation.Kind,
        matcher: LeftoverMatcher,
        bundle: String
    ) -> LeftoverMatch? {
        guard kind != .commandLineTools else { return leadsInside(bundle, link: url) }
        let byName = matcher.match(fileName: name, kind: kind)
        guard let inside = runsSomethingInside(bundle, job: url, kind: kind) else {
            guard byName == nil, let identifier = DeclaredIdentifier.of(url, kind: kind) else { return byName }
            // `.elsewhere`, so no extension is taken off the identifier as if it were a file name.
            return matcher.match(fileName: identifier, kind: .elsewhere)
        }
        return byName?.confidence == .certain ? byName : inside
    }

    /// True for a folder another installed app claims, or one Apple named for itself. A name found inside it
    /// is only a guess: `Caches/com.apple.python/Library/Developer` is not the Developer app's.
    private static func isSomebodyElses(_ name: String, kind: SearchLocation.Kind, matcher: LeftoverMatcher) -> Bool {
        ProtectedData.isApplesName(name) || !matcher.othersClaiming(fileName: name, kind: kind).isEmpty
    }

    /// A job that runs a program inside the app is that app's, whatever it is called: `com.maker.updater.plist`
    /// carries no name of the app it keeps up to date. No rival is named, because a path inside one bundle
    /// cannot be inside another.
    private static func runsSomethingInside(_ bundle: String, job url: URL, kind: SearchLocation.Kind) -> LeftoverMatch? {
        guard kind == .launchAgents || kind == .launchDaemons, url.pathExtension == "plist" else { return nil }
        guard let program = JobDefinition(contentsOf: url)?.program, program.hasPrefix("/") else { return nil }
        let path = PathPattern.comparablePath(of: URL(filePath: program))
        guard PathComponents.isPath(path, atOrInside: bundle) else { return nil }
        return LeftoverMatch(reason: .launchdJob, confidence: .certain, sharedWith: [])
    }

    /// A link that leads inside the app is that app's, whatever the tool is called. A link that leads anywhere
    /// else is not claimed. The link is read without following it, and a relative one is taken from its folder.
    private static func leadsInside(_ bundle: String, link url: URL) -> LeftoverMatch? {
        guard let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: url.path(percentEncoded: false)) else { return nil }
        let target = URL(filePath: destination, relativeTo: url.deletingLastPathComponent()).standardizedFileURL
        let path = PathPattern.comparablePath(of: target)
        guard PathComponents.isPath(path, inside: bundle) else { return nil }
        return LeftoverMatch(reason: .linksToTheApp, confidence: .certain, sharedWith: [])
    }

    /// True for a home item that many tools share, such as `~/.local`, which an app called Local would claim.
    /// `RemovalGuard` refuses these, so listing one would only offer a checkmark that fails later. What is inside
    /// them is still searched by `nested(in:)`.
    private static func isSharedWithTheWholeMac(_ url: URL, home: String) -> Bool {
        ProtectedData.isSharedHomeItem(url.path(percentEncoded: false), home: home)
    }
}
