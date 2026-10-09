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
    /// The most folders listed per location while searching inside folders the app does not claim.
    private let nestedFolderLimit: Int

    public init(environment: SearchEnvironment = .current, exclusions: Exclusions = .none) {
        self.init(environment: environment, exclusions: exclusions, measure: Self.walk)
    }

    static let walk: Measure = { await FileSize.contents(of: $0) }

    /// For tests, which say how each folder answers and can count what the guard is asked.
    init(
        environment: SearchEnvironment,
        exclusions: Exclusions = .none,
        measure: @escaping Measure,
        refuses: @escaping Refuses = { ProtectedData.refuses($0, home: $1) },
        nestedFolderLimit: Int = NestedSearch.folderLimit
    ) {
        self.environment = environment
        self.exclusions = exclusions
        self.measure = measure
        self.refuses = refuses
        self.nestedFolderLimit = nestedFolderLimit
    }

    /// Finds the files `app` keeps outside its bundle. `installedApps` should hold every app on the Mac, so files
    /// other apps use are marked as shared.
    @concurrent
    public func scan(_ app: InstalledApp, installedApps: [InstalledApp]) async -> LeftoverScan {
        await scan(app, matcher: matcher(for: app, installedApps: installedApps))
    }

    /// What tells `app`'s files from those of every other app. The apps macOS ships are rivals too: Apple keeps
    /// folders under their names (`Application Support/Music`) that an app of the same name would otherwise get
    /// outright. So are the apps macOS knows outside the list that may use the same files (`appsElsewhere`).
    func matcher(for app: InstalledApp, installedApps: [InstalledApp]) async -> LeftoverMatcher {
        let known = installedApps + (await AppCatalog.systemApps.value)
        // An app Peel saw installed is an app of its own once it is gone too, not a helper of this one.
        let remembered = await AppMemory(url: AppMemory.url(inHome: environment.homeDirectory)).load()
        let places = Dictionary(
            remembered.map {
                ($0.bundleIdentifier.lowercased(), URL(filePath: $0.lastPath, directoryHint: .isDirectory))
            },
            uniquingKeysWith: { first, _ in first }
        )
        return LeftoverMatcher(app: app, installedApps: known + (await appsElsewhere(like: app, besides: known))) {
            AppInspector.applicationURL(forBundleIdentifier: $0) ?? places[$0.lowercased()]
        }
    }

    /// The apps macOS knows, outside `known`, that may use `app`'s files: every other copy of it, such as an older one
    /// kept in Downloads or one on another disk, and the apps of the same maker, such as a Nightly build beside it.
    /// Spotlight names the maker's apps and Launch Services says where each is installed, so a copy inside a backup
    /// never counts.
    private func appsElsewhere(like app: InstalledApp, besides known: [InstalledApp]) async -> [InstalledApp] {
        let own = app.bundleIdentifier.lowercased()
        let makers = await AppInspector.indexedIdentifiers(beginningWith: Self.makersPrefixes(of: app.bundleIdentifier))
        let identifiers = [app.bundleIdentifier] + makers.filter { $0.lowercased() != own }.sorted()
        let wanted = Set(identifiers.map { $0.lowercased() })
        let bundle = PathPattern.comparablePath(of: PathPattern.canonical(app.url))
        let listed = Set(
            known.filter { wanted.contains($0.bundleIdentifier.lowercased()) }
                .map { PathPattern.comparablePath(of: PathPattern.canonical($0.url)) }
        )
        return identifiers.flatMap(AppInspector.applicationURLs).filter { url in
            let path = PathPattern.comparablePath(of: PathPattern.canonical(url))
            return !listed.contains(path) && !PathComponents.isPath(path, atOrInside: bundle)
                && environment.keepsOnItsOwn(appAt: path)
        }.compactMap(AppInspector.inspect)
    }

    /// How the identifiers of the maker's apps begin, its Mac Catalyst builds' included. None for Apple's own apps:
    /// the list of what macOS ships holds them, and Spotlight would name them whole.
    static func makersPrefixes(of identifier: String) -> [String] {
        guard
            let vendor = Identifier.vendor(of: identifier),
            !ProtectedData.isApplesName(vendor + ".")
        else { return [] }
        return [vendor + ".", Identifier.catalystPrefix + vendor + "."]
    }

    @concurrent
    func scan(_ app: InstalledApp, matcher: LeftoverMatcher) async -> LeftoverScan {
        let results = await withTaskGroup(of: (location: SearchLocation, result: LocationResult).self) { group in
            // Safari's web app container is read only for one of its web apps: anything inside another app's
            // container makes macOS ask for its data unless Peel has Full Disk Access.
            for location in environment.locations where location.kind != .safariWebApps || app.isASafariWebApp {
                let home = environment.homeDirectory.path(percentEncoded: false)
                let bundle = PathPattern.comparablePath(of: app.url)
                _ = group.addTaskUnlessCancelled { [exclusions, measure, refuses, nestedFolderLimit] in
                    (location, await Self.scan(
                        location,
                        matcher: matcher,
                        home: home,
                        bundle: bundle,
                        exclusions: exclusions,
                        measure: measure,
                        refuses: refuses, nestedFolderLimit: nestedFolderLimit
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
            case .found(let leftovers, let cutShort, let unreadable):
                found.append((location, leftovers))
                if let cutShort { cutShortLocations.append(cutShort) }
                unreadableLocations += unreadable
            case .unreadable(let location):
                unreadableLocations.append(location)
            }
        }
        let leftovers = Self.merged(found)

        let byPath: (SearchLocation, SearchLocation) -> Bool = {
            $0.url.path(percentEncoded: false) < $1.url.path(percentEncoded: false)
        }
        return LeftoverScan(
            leftovers: leftovers
                .map { exclusions.holds($0.url) ? $0.heldBack(.holdsAnExclusion) : $0 }
                .sorted(by: Leftover.comesBefore),
            unreadableLocations: unreadableLocations.sorted(by: byPath),
            cutShortLocations: cutShortLocations.sorted(by: byPath),
            needsFullDiskAccess: unreadableLocations.contains { FullDiskAccess.canList($0.url) == .missing }
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
            guard depth(one.location) == depth(other.location) else {
                return depth(one.location) > depth(other.location)
            }
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
        /// `cutShort` is the location itself when the search inside its folders hit the limit, and `unreadable` the
        /// folders inside it that search could not look into.
        case found([Leftover], cutShort: SearchLocation?, unreadable: [SearchLocation])
        case unreadable(SearchLocation)
    }

    /// Kinds of location that belong to macOS or to the user, where a match on the app's name alone is a guess:
    /// there is a real app called Developer, and `~/Library/Developer` is Xcode's.
    private static let namedGroundOfSomebodyElse: Set<SearchLocation.Kind> = [.hiddenHomeFiles, .library, .homeFolder]

    private static func scan(
        _ location: SearchLocation,
        matcher: LeftoverMatcher,
        home: String,
        bundle: String,
        exclusions: Exclusions,
        measure: @escaping Measure,
        refuses: Refuses,
        nestedFolderLimit: Int
    ) async -> LocationResult {
        let entries: [String]
        do {
            // Sorted, because Apple documents the order of a listing as undefined, and with a limit on how many
            // folders are looked into, the order decides which ones.
            entries = try FileManager.default.contentsOfDirectory(atPath: location.url.path(percentEncoded: false))
                .sorted()
            ScanCount.current?.add(entries.count)
        } catch CocoaError.fileReadNoSuchFile {
            return .found([], cutShort: nil, unreadable: [])
        } catch {
            return .unreadable(location)
        }

        let parent = ParentAccess(location.url)
        var toMeasure: [Found] = []
        var nobodysFolders: [URL] = []

        // The guard reads every spelling of a path from the disk, so it is asked only about what the scan would
        // take or walk into, and what it refuses is left out of both, as is what the person excluded.
        for name in entries where location.considers(fileName: name) {
            // A canceled scan stops here, since nobody will read what it finds.
            guard !Task.isCancelled else { break }
            let url = location.url.appending(path: name)
            let path = url.path(percentEncoded: false)
            if let match = claim(name, at: url, kind: location.kind, matcher: matcher, bundle: bundle),
               !isSharedWithTheWholeMac(url, home: home) {
                guard !refuses(path, home), !exclusions.excludes(url), !FileAccess.cannotBeRemoved(url) else {
                    continue
                }
                toMeasure.append(Found(url: url, match: match, parent: parent, foldersAbove: .itsOwn))
            } else if NestedSearch.kinds.contains(location.kind), url.isRealFolder, !refuses(path, home),
                      !exclusions.excludes(url) {
                nobodysFolders.append(url)
            }
        }

        let leftovers = await measured(toMeasure, kind: location.kind, home: home, measure: measure)
        let inside = await nested(
            in: nobodysFolders, of: location, matcher: matcher, home: home, bundle: bundle, exclusions: exclusions,
            measure: measure, refuses: refuses, limit: nestedFolderLimit
        )
        return .found(
            leftovers + inside.found, cutShort: inside.wasCutShort ? location : nil,
            unreadable: inside.unreadable.map { SearchLocation(kind: location.kind, url: $0) }
        )
    }

    /// Looks inside the folders not taken as the app's. Only a match strong enough to name the app on its own
    /// (`likely` or better) is taken, because everything else in there is somebody else's.
    private static func nested(
        in folders: [URL],
        of location: SearchLocation,
        matcher: LeftoverMatcher,
        home: String,
        bundle: String,
        exclusions: Exclusions,
        measure: @escaping Measure,
        refuses: Refuses,
        limit: Int
    ) async -> (found: [Leftover], wasCutShort: Bool, unreadable: [URL]) {
        let kind = location.kind
        let locationLength = location.url.pathComponents.count
        let search: NestedSearch.Findings<Found> = await NestedSearch.walk(inside: folders, limit: limit) {
            url, name, parent, canLookInside in
            let path = url.path(percentEncoded: false)
            // A browser's manifest is whoever's program it runs, whatever it is called.
            let match = url.deletingLastPathComponent().lastPathComponent.lowercased() == "nativemessaginghosts"
                ? runsSomethingInside(bundle, manifest: url) : Self.match(name, at: url, kind: kind, matcher: matcher)
            if let match, match.confidence >= .likely,
               !isSharedWithTheWholeMac(url, home: home) {
                guard !refuses(path, home), !exclusions.excludes(url) else { return .pass }
                // Whose the folders on the way are decides what its name is worth.
                let between = url.deletingLastPathComponent().pathComponents.dropFirst(locationLength)
                return .take(Found(
                    url: url, match: match, parent: parent,
                    foldersAbove: foldersAbove(between, kind: kind, matcher: matcher)
                ))
            }
            guard canLookInside, url.isRealFolder, !refuses(path, home), !exclusions.excludes(url) else { return .pass }
            return .lookInside
        }
        let found = await measured(search.found, kind: kind, home: home, measure: measure)
        return (found, search.wasCutShort, search.unreadable)
    }

    /// Something a search took as the app's, waiting to be measured.
    private struct Found: Sendable {
        let url: URL
        let match: LeftoverMatch
        let parent: ParentAccess
        let foldersAbove: FoldersAbove
    }

    /// Whose the folders between a search location and an item found inside them are.
    enum FoldersAbove: Sendable {
        /// None, or each named for the app or its maker.
        case itsOwn
        /// One is Apple's or another installed app's.
        case anotherApps
        /// One is named for neither the app nor its maker, so it may be any program's.
        case unknown
    }

    private static func foldersAbove(
        _ folders: some Collection<String>, kind: SearchLocation.Kind, matcher: LeftoverMatcher
    ) -> FoldersAbove {
        if folders.contains(where: { isSomebodyElses($0, kind: kind, matcher: matcher) }) { return .anotherApps }
        return folders.allSatisfy(matcher.namesTheAppOrItsMaker(folder:)) ? .itsOwn : .unknown
    }

    /// How many items of one location are measured at once. One after another, a few folders that never answer
    /// would each hold the location for the whole budget of `FileSize`.
    static let concurrentMeasurements = 4

    /// Measures what one location found, a few at a time, and keeps the order it was found in.
    private static func measured(
        _ found: [Found], kind: SearchLocation.Kind, home: String, measure: @escaping Measure
    ) async -> [Leftover] {
        await found.concurrentMap(width: concurrentMeasurements) { item in
            await leftover(
                at: item.url, kind: kind, match: item.match, parent: item.parent, home: home,
                foldersAbove: item.foldersAbove, measure: measure
            )
        }
    }

    /// Builds a leftover: measures it and decides whether to hold it back. The scan, cask paths, and installer
    /// receipts all come through here, so the same rules apply to every leftover.
    static func leftover(
        at url: URL,
        kind: SearchLocation.Kind,
        match: LeftoverMatch,
        parent: ParentAccess,
        home: String,
        foldersAbove: FoldersAbove = .itsOwn,
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
        } else if ProtectedData.holdsWorkKeptInACache(url.path(percentEncoded: false)) {
            .holdsWorkKeptInACache
        } else if let keptOnlyHere = KeptOnlyHere.reason(for: url.path(percentEncoded: false), home: home) {
            keptOnlyHere
        } else if contents?.couldNotBeRead == true {
            .couldNotBeRead
        } else if let contents {
            heldBack(match, at: url, in: kind, contents: contents, foldersAbove: foldersAbove)
        } else {
            .notMeasured
        }
        return Leftover(
            url: url,
            kind: kind,
            match: heldBack.map(match.forReview) ?? match,
            size: contents?.size ?? 0,
            isMeasured: contents.map { !$0.couldNotBeRead } ?? false,
            requiresPrivileges: parent.requiresPrivileges(toRemove: url),
            holdsDamagedSettings: kind == .preferences && PreferenceFile.isDamaged(url)
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
        at url: URL,
        in kind: SearchLocation.Kind,
        contents: FolderContents,
        foldersAbove: FoldersAbove
    ) -> HoldBack? {
        // A wallet comes first: a cask's `zap` can name a coin app's whole data folder, which is where its keys
        // are. Holding it back costs a checkmark, and the row says what is inside.
        if let secret = HoldBack.secret(in: contents) { return secret }
        if contents.holdsRepository { return .holdsRepository }
        if kind == .logs, CrashReport.isOne(url) { return .crashReport }
        if kind == .sharedFolder { return .sharedWithEveryone }
        if Self.namedGroundOfSomebodyElse.contains(kind), match.restsOnAName { return .namedLikeTheApp }
        // An identifier names the app wherever it sits. Its name, inside somebody else's folder, does not.
        if match.restsOnAName, foldersAbove == .anotherApps { return .insideAnotherAppsFolder }
        if match.restsOnAName, foldersAbove == .unknown { return .namedLikeTheApp }
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
        guard !kind.isForLinks else { return leadsInside(bundle, link: url) }
        guard kind != .nativeMessagingHosts else { return runsSomethingInside(bundle, manifest: url) }
        guard let inside = runsSomethingInside(bundle, job: url, kind: kind) else {
            return match(name, at: url, kind: kind, matcher: matcher)
        }
        let byName = matcher.match(fileName: name, kind: kind, at: url)
        return byName?.confidence == .certain ? byName : inside
    }

    /// This app's claim on an item from its name and from the identifier it declares, which is read for a plug-in, a
    /// crash report, and an item whose name answers nothing. The identifier says whose such an item is: a claim
    /// through it replaces a weaker one on the name, and a name it does not back makes the item only possible.
    private static func match(
        _ name: String,
        at url: URL,
        kind: SearchLocation.Kind,
        matcher: LeftoverMatcher
    ) -> LeftoverMatch? {
        // A system extension macOS activated is its own to remove: it uninstalls one with the app it came in.
        guard url.pathExtension.lowercased() != "systemextension" else { return nil }
        let byName = DeclaredIdentifier.nameSaysNothing(of: url, kind: kind)
            ? nil : matcher.match(fileName: name, kind: kind, at: url)
        guard byName == nil || DeclaredIdentifier.outranksTheName(of: url, kind: kind) else { return byName }
        // `.elsewhere`, so no extension is taken off the identifier as if it were a file name.
        let declared = DeclaredIdentifier.of(url, kind: kind).flatMap {
            matcher.match(fileName: $0, kind: .elsewhere, at: url)
        }
        guard let byName else { return declared }
        guard let declared else { return byName.restsOnAName ? byName.atMost(.possible) : byName }
        return declared.confidence >= byName.confidence ? declared : byName
    }

    /// True for a folder another installed app claims, or one Apple named for itself. A name found inside it
    /// is only a guess: `Caches/com.apple.python/Library/Developer` is not the Developer app's. Another copy of
    /// the app is no one else.
    private static func isSomebodyElses(_ name: String, kind: SearchLocation.Kind, matcher: LeftoverMatcher) -> Bool {
        ProtectedData.isApplesName(name) || !matcher.othersClaiming(fileName: name, kind: kind).apps.isEmpty
    }

    /// A job that runs a program inside the app is that app's, whatever it is called: `com.maker.updater.plist`
    /// carries no name of the app it keeps up to date. No rival is named, because a path inside one bundle
    /// cannot be inside another.
    private static func runsSomethingInside(
        _ bundle: String,
        job url: URL,
        kind: SearchLocation.Kind
    ) -> LeftoverMatch? {
        guard let program = LeftoverMatcher.program(ofJobAt: url, kind: kind),
              PathComponents.isPath(program, atOrInside: bundle)
        else { return nil }
        return LeftoverMatch(reason: .launchdJob, confidence: .certain, sharedWith: [])
    }

    /// A browser's native messaging manifest is the app's when the program it names, an absolute path, is inside it.
    private static func runsSomethingInside(_ bundle: String, manifest url: URL) -> LeftoverMatch? {
        guard url.pathExtension == "json", let data = BoundedRead.data(at: url, maximum: 64 * 1_024),
              let manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let program = manifest["path"] as? String, program.hasPrefix("/")
        else { return nil }
        let path = PathPattern.comparablePath(of: URL(filePath: program))
        guard PathComponents.isPath(path, atOrInside: bundle) else { return nil }
        return LeftoverMatch(reason: .nativeMessagingHost, confidence: .certain, sharedWith: [])
    }

    /// A link that leads inside the app is that app's, whatever the tool is called. A link that leads anywhere
    /// else is not claimed. The link is read without following it, and a relative one is taken from its folder.
    private static func leadsInside(_ bundle: String, link url: URL) -> LeftoverMatch? {
        guard
            let destination = try? FileManager.default.destinationOfSymbolicLink(
                atPath: url.path(percentEncoded: false)
            )
        else { return nil }
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
