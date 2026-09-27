public import Foundation
internal import PeelPrivileged

/// An app, the files it leaves behind, and which of them need administrator rights to move.
public struct Uninstallation: Sendable {
    public let app: InstalledApp
    public let appSize: Int64
    public let appRequiresPrivileges: Bool
    public let scan: LeftoverScan
    /// The user asked Peel to leave this app alone, so nothing of it is offered or moved.
    public var isExcluded = false
    /// False when the bundle did not answer in time, so `appSize` is not known rather than zero.
    public var isAppMeasured = true
    /// True when the app needs administrator rights and the helper may not move it. The app is then never
    /// selected: its leftovers would move first, and the app would stay without them.
    public var isAppBeyondTheHelper = false
    /// True for Peel, which is removed only from its own Settings, where its helper and login item go first. Its
    /// files are listed, and nothing of it is selected or moved anywhere else: `unreviewedSelection` is that way.
    public var isPeel: Bool { app.isPeelItself }

    @concurrent
    public static func prepare(
        _ app: InstalledApp,
        installedApps: [InstalledApp],
        exclusions: Exclusions = .none,
        casks: [HomebrewPackage] = [],
        receipts: Set<String> = [],
        environment: SearchEnvironment = .current
    ) async -> Uninstallation {
        async let bundle = FileSize.contents(of: app.url)
        guard !exclusions.excludes(app) else {
            return Uninstallation(
                app: app,
                appSize: await bundle?.size ?? 0,
                appRequiresPrivileges: FileAccess.requiresPrivilegesToRemove(app.url),
                scan: LeftoverScan(leftovers: [], unreadableLocations: []),
                isExcluded: true,
                isAppMeasured: await bundle.map { !$0.couldNotBeRead } ?? false
            )
        }
        let scanner = LeftoverScanner(environment: environment, exclusions: exclusions)
        let matcher = await scanner.matcher(for: app, installedApps: installedApps)
        var scan = await scanner.scan(app, matcher: matcher)
        if let evidence = CaskEvidence.evidence(for: app, casks: casks, home: environment.homeDirectory) {
            scan = scan.adding(await caskLeftovers(evidence, app: app, exclusions: exclusions, matcher: matcher, environment: environment))
        }
        scan = scan.adding(await receiptLeftovers(for: app, receipts: receipts, exclusions: exclusions, environment: environment))
        let reach = HelperReach(environment: environment)
        scan = scan.holdingBack(beyond: reach, leaving: app.url)
        let appRequiresPrivileges = FileAccess.requiresPrivilegesToRemove(app.url)
        return Uninstallation(
            app: app,
            appSize: await bundle?.size ?? 0,
            appRequiresPrivileges: appRequiresPrivileges,
            scan: scan,
            isAppMeasured: await bundle.map { !$0.couldNotBeRead } ?? false,
            isAppBeyondTheHelper: appRequiresPrivileges && !app.isSystemProtected && reach.isBeyond(app.url)
        )
    }

    /// The installer receipt files that belong to `app`. The receipt is the only reason macOS still counts the
    /// package as installed once the app is gone, and it is two small files the Trash can give back. What the
    /// package installed elsewhere is left to the Package Receipts page, which weighs each item on its own.
    static func receiptLeftovers(
        for app: InstalledApp,
        receipts: Set<String>,
        exclusions: Exclusions,
        environment: SearchEnvironment
    ) async -> [Leftover] {
        let identifier = app.bundleIdentifier.lowercased()
        var leftovers: [Leftover] = []
        for receipt in receipts.filter({ PackageReceipts.proves($0, isThe: identifier) }).sorted() {
            for url in PackageActions.receiptFiles(of: receipt, onVolume: environment.rootDirectory) where !exclusions.excludes(url) {
                leftovers.append(await LeftoverScanner.leftover(
                    at: url,
                    kind: .receipts,
                    match: LeftoverMatch(reason: .installerReceipt, confidence: .certain, sharedWith: []),
                    parent: ParentAccess(url.deletingLastPathComponent()),
                    home: environment.homeDirectory.path(percentEncoded: false)
                ))
            }
        }
        return leftovers
    }

    /// Leftovers for the paths a cask names (`LeftoverScan.adding` drops those the scanner already found).
    /// Homebrew warns that `zap` may remove what other apps share, and a vendor's shared folder is exactly what
    /// only a cask would name. So a path in a Library is `likely` only when the app's own matcher also matches it.
    /// Every other path is `possible`: shown, never preselected.
    static func caskLeftovers(
        _ evidence: CaskEvidence,
        app: InstalledApp,
        exclusions: Exclusions,
        matcher: LeftoverMatcher,
        environment: SearchEnvironment
    ) async -> [Leftover] {
        var leftovers: [Leftover] = []
        // Compared by path: the app's URL ends in a slash and a cask's path does not, and many casks list the app
        // among what they delete. What sits inside the bundle is skipped too: it goes with the app, and moved on
        // its own it would be cut out of an app that stays.
        let bundle = PathPattern.comparablePath(of: app.url)
        for item in evidence.items where !exclusions.excludes(item.url) && !isAtOrInside(bundle, item.url) {
            let place = place(of: item.url, in: environment)
            let own = matcher.match(fileName: item.url.lastPathComponent, kind: place.kind, at: item.url)
            // Every folder on the way counts: a path inside a folder another app claims is not this app's alone.
            let claims = place.components.map { matcher.othersClaiming(fileName: $0, kind: place.kind) }
            let leftover = await LeftoverScanner.leftover(
                at: item.url,
                kind: place.kind,
                match: LeftoverMatch(
                    reason: .homebrewCask,
                    confidence: item.isInLibrary && own != nil ? .likely : .possible,
                    sharedWith: Set(claims.flatMap(\.apps)).union(own?.sharedWith ?? []).sorted(),
                    otherCopies: claims.flatMap(\.copies) + (own?.otherCopies ?? [])
                ),
                parent: ParentAccess(item.url.deletingLastPathComponent()),
                home: environment.homeDirectory.path(percentEncoded: false)
            )
            leftovers.append(exclusions.holds(item.url) ? leftover.heldBack(.holdsAnExclusion) : leftover)
        }
        return leftovers
    }

    private static func isAtOrInside(_ folder: String, _ url: URL) -> Bool {
        let path = PathPattern.comparablePath(of: url)
        return PathComponents.isPath(path, atOrInside: folder)
    }

    /// The kind of scanned location `url` sits in, which says how its name is read (a `.plist` in Preferences
    /// names a domain), and the path components from that location down to the item. Outside every scanned
    /// location, the kind is `.elsewhere`.
    static func place(of url: URL, in environment: SearchEnvironment) -> (kind: SearchLocation.Kind, components: [String]) {
        let path = PathPattern.comparablePath(of: url)
        let inside = environment.locations
            .map { (kind: $0.kind, root: PathPattern.comparablePath(of: $0.url)) }
            .filter { PathComponents.isPath(path, inside: $0.root) }
            // Two locations can share a root, like the hidden and plain halves of the home folder. The one that
            // considers this name is the one that would have found it.
            .filter { location in
                guard let first = PathComponents.of(path.dropFirst(location.root.count + 1)).first else { return false }
                return location.kind.considers(fileName: first)
            }
            .max { $0.root.count < $1.root.count }
        guard let inside else { return (.elsewhere, [url.lastPathComponent]) }
        let components = PathComponents.of(path.dropFirst(inside.root.count + 1))
        // The home folder is a location only for what sits directly in it; below that is the user's own.
        guard inside.root != PathPattern.comparablePath(of: environment.homeDirectory) || components.count == 1 else {
            return (.elsewhere, [url.lastPathComponent])
        }
        return (inside.kind, components)
    }

    /// True when the app itself would stay: excluded, Peel, kept by macOS, beyond the helper, or needing the
    /// helper while it is not there. Nothing of it is then selected for the user: what it left behind would go
    /// first, and it would stay without its settings. For an app macOS keeps, what it holds is data in use.
    public func appStays(canUseHelper: Bool) -> Bool {
        isExcluded || isPeel || app.isSystemProtected || isAppBeyondTheHelper || (appRequiresPrivileges && !canUseHelper)
    }

    /// What is selected for the user at first: the app and the recommended leftovers that can move. Empty for
    /// an app that would stay (`appStays(canUseHelper:)`).
    public func suggestedSelection(canUseHelper: Bool) -> Set<URL> {
        guard !appStays(canUseHelper: canUseHelper) else { return [] }
        var selection = Set(scan.leftovers.filter { $0.match.isRecommended && (canUseHelper || !$0.requiresPrivileges) }.map(\.url))
        selection.insert(app.url)
        return selection
    }

    /// What a checkbox on the app's page can select: nothing Peel leaves alone or with something excluded inside,
    /// nothing that needs the helper while it cannot act, and nothing of an excluded app or of Peel.
    public func selectable(canUseHelper: Bool) -> Set<URL> {
        guard !isExcluded, !isPeel else { return [] }
        var urls = Set(scan.leftovers.filter { leftover in
            leftover.match.heldBack != .holdsAnExclusion && leftover.match.heldBack?.cannotBeMoved != true
                && (canUseHelper || !leftover.requiresPrivileges)
        }.map(\.url))
        if !app.isSystemProtected, !isAppBeyondTheHelper, canUseHelper || !appRequiresPrivileges {
            urls.insert(app.url)
        }
        return urls
    }

    /// What moves when nobody reviews the list, as when Peel removes itself: the app, plus the recommended
    /// leftovers that need no helper and are certainly its own or named inside its bundle identifier (a
    /// namespace only its maker uses). Empty when the app is excluded, kept by macOS, or needs the helper: then
    /// nothing should start.
    public var unreviewedSelection: [URL] {
        guard !isExcluded, !app.isSystemProtected, !appRequiresPrivileges else { return [] }
        let namespace = app.bundleIdentifier.lowercased() + "."
        let own = scan.leftovers.filter { leftover in
            leftover.match.isRecommended && !leftover.requiresPrivileges
                && (leftover.match.confidence == .certain || leftover.url.lastPathComponent.lowercased().hasPrefix(namespace))
        }
        return order(of: Set(own.map(\.url)).union([app.url]))
    }

    /// How many items could move once selected, and their total size: what a section header shows and the
    /// page's total adds up. Rows Peel leaves alone are not counted.
    public func movable(among leftovers: [Leftover], withApp: Bool) -> (count: Int, size: SizeTotal) {
        guard !isPeel else { return (0, SizeTotal([])) }
        var sizes: [Int64?] = leftovers
            .filter { $0.match.heldBack?.cannotBeMoved != true && $0.match.heldBack != .holdsAnExclusion }
            .map { $0.isMeasured ? $0.size : nil }
        if withApp, !app.isSystemProtected, !isExcluded, !isAppBeyondTheHelper {
            sizes.append(isAppMeasured ? appSize : nil)
        }
        return (sizes.count, SizeTotal(sizes))
    }

    public var privilegedURLs: Set<URL> {
        guard !isExcluded, !isPeel else { return [] }
        var urls = Set(scan.leftovers.filter { $0.requiresPrivileges && $0.match.heldBack != .beyondTheHelper }.map(\.url))
        if appRequiresPrivileges, !app.isSystemProtected, !isAppBeyondTheHelper {
            urls.insert(app.url)
        }
        return urls
    }

    /// The selected leftovers, then the app itself.
    public func removalOrder(of selection: Set<URL>) -> [URL] {
        guard !isExcluded, !isPeel else { return [] }
        return order(of: selection)
    }

    private func order(of selection: Set<URL>) -> [URL] {
        scan.leftovers.map(\.url).filter(selection.contains) + (selection.contains(app.url) ? [app.url] : [])
    }
}
