public import Foundation

/// An uninstall of several apps at once. Each file is listed once, and a file shared only among the chosen apps
/// can go with them, unless one of them stays (`staying(selected:)`).
public struct BulkUninstallation: Sendable {
    public struct Item: Sendable, Hashable, Identifiable {
        public let url: URL
        public let size: Int64
        public let kind: SearchLocation.Kind?
        public let requiresPrivileges: Bool
        /// The chosen apps this item belongs to, by `InstalledApp.reference`.
        public let apps: [String]
        public let match: LeftoverMatch?
        /// The apps outside the selection that also claim this item, by `InstalledApp.reference`.
        public let sharedWithOthers: [String]
        /// Other copies of a chosen app, not chosen themselves, that use this item too.
        public var otherCopies: [URL] = []
        /// An excluded app, or an item with something excluded inside. Shown, never selected, never moved.
        public var isExcluded = false
        /// An app macOS protects, or an item found for one. The app stays, so none of it is a leftover to select.
        public var isKeptByMacOS = false
        /// False when the size could not be measured, so `size` is unknown rather than zero.
        public var isMeasured = true
        /// Needs administrator rights, and the helper may not move it. Shown, never selected, never moved.
        public var isBeyondTheHelper = false
        /// How an app removed elsewhere is removed instead, for it and its files: Peel by Remove Peel, an agent by its
        /// maker's uninstaller. Shown, never selected, never moved.
        public var removedElsewhere: RemovedElsewhere?
        /// An app's bundle already in the Trash. Shown, never selected, never counted.
        public var isInTheTrash = false
        /// The package an app's bundle sits inside (`InstalledApp.enclosingPackage`). Shown, never selected, never
        /// moved.
        public var enclosingPackage: URL?
        /// True for a preference file that is no property list (`PreferenceFile.isDamaged`).
        public var holdsDamagedSettings = false

        public var id: URL { url }

        public var isApplication: Bool { match == nil }
        public var isRecommended: Bool {
            guard !isExcluded, removedElsewhere == nil, !isKeptByMacOS, !isBeyondTheHelper, !isInTheTrash,
                  enclosingPackage == nil
            else {
                return false
            }
            guard let match else { return true }
            return sharedWithOthers.isEmpty && otherCopies.isEmpty && match.confidence >= .likely
                && match.heldBack == nil
        }
    }

    public let uninstallations: [Uninstallation]
    public let items: [Item]
    /// The size of what could be moved, counted by the same rule as an app's own page: nothing the user
    /// excluded, no app macOS protects, and no row that can never be moved. An unmeasured row is never counted
    /// as zero: it makes the total incomplete.
    public let total: SizeTotal
    public let privilegedURLs: Set<URL>

    public var apps: [InstalledApp] { uninstallations.map(\.app) }
    public var needsFullDiskAccess: Bool {
        uninstallations.contains { $0.scan.needsFullDiskAccess }
    }
    public var unreadableLocations: [SearchLocation] {
        Array(Set(uninstallations.flatMap { $0.scan.unreadableLocations })).sorted {
            $0.url.path(percentEncoded: false) < $1.url.path(percentEncoded: false)
        }
    }

    public init(uninstallations: [Uninstallation]) {
        let items = Self.merge(uninstallations)
        self.uninstallations = uninstallations
        self.items = items
        total = SizeTotal(movingItemsAt: Dictionary(items
            .filter {
                !$0.isExcluded && $0.removedElsewhere == nil && !($0.isApplication && $0.isKeptByMacOS)
                    && !$0.isBeyondTheHelper
                    && !$0.isInTheTrash && $0.enclosingPackage == nil && $0.match?.heldBack?.cannotBeMoved != true
            }
            .map { ($0.url, $0.isMeasured ? $0.size : nil) }) { first, _ in first })
        privilegedURLs = Set(
            items.filter {
                $0.requiresPrivileges && !$0.isExcluded && $0.removedElsewhere == nil && !$0.isBeyondTheHelper
                    && !$0.isInTheTrash
                    && $0.enclosingPackage == nil && !($0.isApplication && $0.isKeptByMacOS)
            }.map(\.url)
        )
    }

    @concurrent
    public static func prepare(
        _ apps: [InstalledApp],
        installedApps: [InstalledApp],
        exclusions: Exclusions = .none,
        casks: [HomebrewPackage] = [],
        receipts: Set<String> = [],
        systemExtensions: AppExtensions.SystemExtensionsAnswer = AppExtensions.askingMacOS,
        environment: SearchEnvironment = .current
    ) async -> BulkUninstallation {
        let carriesOne = apps.contains { !AppExtensions.systemExtensions(carriedBy: $0.url).isEmpty }
        let installed = carriesOne ? await systemExtensions() : nil
        var prepared: [Uninstallation] = []
        for app in apps where !Task.isCancelled {
            prepared.append(
                await Uninstallation.prepare(
                    app,
                    installedApps: installedApps,
                    exclusions: exclusions,
                    casks: casks,
                    receipts: receipts,
                    systemExtensions: { installed },
                    environment: environment
                )
            )
        }
        return BulkUninstallation(uninstallations: prepared)
    }

    /// What is selected for the user at first. Nothing of an app that would stay, as on its own page, and that
    /// includes what it shares with another chosen app: it goes on using it.
    public func suggestedSelection(canUseHelper: Bool) -> Set<URL> {
        let staying = Set(
            uninstallations.filter { $0.appStays(canUseHelper: canUseHelper) }.map(\.app.reference)
        )
        return Set(items.filter { item in
            item.isRecommended && (canUseHelper || !item.requiresPrivileges)
                && !item.apps.contains(where: staying.contains)
        }.map(\.url))
    }

    /// What a checkbox can select, by the rule of an app's own page: nothing Peel leaves alone or with something
    /// excluded inside, nothing that needs the helper while it cannot act, no app macOS keeps, that sits inside
    /// another package, or that the helper may not move, and nothing of Peel.
    public func selectable(canUseHelper: Bool) -> Set<URL> {
        Set(items.filter { item in
            !item.isExcluded && item.removedElsewhere == nil && !item.isBeyondTheHelper && !item.isInTheTrash
                && item.enclosingPackage == nil
                && !(item.isApplication && item.isKeptByMacOS) && item.match?.heldBack?.cannotBeMoved != true
                && (canUseHelper || !item.requiresPrivileges)
        }.map(\.url))
    }

    /// The files of the app `reference` names (`InstalledApp.reference`): its leftovers, and what it shares with
    /// another chosen app. Two copies of an app share these, and each has a bundle of its own.
    public func files(of reference: String) -> Set<URL> {
        Set(items.filter { !$0.isApplication && $0.apps.contains(reference) }.map(\.url))
    }

    /// The chosen apps that stay, by `InstalledApp.reference`: each one with a copy whose bundle is not selected. That
    /// includes an app that cannot go (`Uninstallation.appStays(canUseHelper:)`), since its bundle never is, and
    /// leaves out a copy already in the Trash, which stays nowhere.
    public func staying(selected: Set<URL>) -> Set<String> {
        Set(
            uninstallations.filter { !$0.isAppInTheTrash && !selected.contains($0.app.url) }.map(\.app.reference)
        )
    }

    /// Returns the selection in the order it is moved: the apps first, then the files. Excluded items and Peel's
    /// are left out.
    public func removalOrder(of selection: Set<URL>) -> [URL] {
        let movable = items.filter { !$0.isExcluded && $0.removedElsewhere == nil && selection.contains($0.url) }
        return movable.filter(\.isApplication).map(\.url) + movable.filter { !$0.isApplication }.map(\.url)
    }

    /// Moves `selection`, the apps first: a file follows only once every selected app it belongs to has moved, so
    /// an app that stays keeps everything of its own, what it shares with another chosen app included.
    public func move(_ selection: Set<URL>, using service: TrashService) async -> TrashResult {
        let order = removalOrder(of: selection)
        let apps = Set(items.filter(\.isApplication).map(\.url))
        let owners = Dictionary(items.map { ($0.url, $0.apps) }, uniquingKeysWith: { first, _ in first })
        let references = Dictionary(
            uninstallations.map { ($0.app.url, $0.app.reference) },
            uniquingKeysWith: { first, _ in first }
        )
        return await service.trash(
            apps: order.filter(apps.contains),
            thenFiles: { stayed in
                let kept = Set(stayed.compactMap { references[$0] })
                return order.filter { !apps.contains($0) && !(owners[$0] ?? []).contains(where: kept.contains) }
            },
            usingHelperFor: privilegedURLs,
            lettingTheirProgramsRun: Set(uninstallations.filter { $0.uninstallsItself != nil }.map(\.app.url)),
            emptiedFoldersNamed: MakersFolders.names(of: uninstallations.map(\.app))
        )
    }

    /// The chosen apps that stayed while files of their own were selected, which then stayed with them.
    public func appsThatKeptTheirFiles(after result: TrashResult, selection: Set<URL>) -> [InstalledApp] {
        let failed = Set(result.failures.map(\.url))
        return apps.filter { app in
            selection.contains(app.url) && failed.contains(app.url)
                && !files(of: app.reference).isDisjoint(with: selection)
        }
    }

    /// The chosen apps `urls` belong to: an app whose bundle is among them, and an app with a file of its own among
    /// them. A file names the app by its reference, which another copy of it shares, so only a bundle names a copy.
    public func apps(owning urls: some Sequence<URL>) -> [InstalledApp] {
        let paths = Set(urls.map(PathPattern.comparablePath))
        let owners = Set(items.filter { paths.contains(PathPattern.comparablePath(of: $0.url)) }.flatMap(\.apps))
        let copied = Set(Dictionary(grouping: apps, by: \.reference).filter { $0.value.count > 1 }.keys)
        return apps.filter { app in
            paths.contains(PathPattern.comparablePath(of: app.url))
                || (owners.contains(app.reference) && !copied.contains(app.reference))
        }
    }

    static func merge(_ uninstallations: [Uninstallation]) -> [Item] {
        let chosen = Set(uninstallations.map(\.app.reference))
        let chosenBundles = Set(uninstallations.map { PathPattern.comparablePath(of: $0.app.url) })
        var byURL: [URL: Item] = [:]
        var order: [URL] = []

        func add(_ item: Item) {
            if let existing = byURL[item.url] {
                byURL[item.url] = Item(
                    url: existing.url,
                    size: max(existing.size, item.size),
                    kind: existing.kind ?? item.kind,
                    requiresPrivileges: existing.requiresPrivileges || item.requiresPrivileges,
                    apps: existing.apps + item.apps.filter { !existing.apps.contains($0) },
                    match: existing.match.flatMap { known in item.match.map(known.combined) } ?? existing.match
                        ?? item.match,
                    sharedWithOthers: existing.sharedWithOthers.filter(item.sharedWithOthers.contains),
                    otherCopies: existing.otherCopies + item.otherCopies.filter { !existing.otherCopies.contains($0) },
                    isExcluded: existing.isExcluded || item.isExcluded,
                    isKeptByMacOS: existing.isKeptByMacOS || item.isKeptByMacOS,
                    isMeasured: existing.isMeasured || item.isMeasured,
                    isBeyondTheHelper: existing.isBeyondTheHelper || item.isBeyondTheHelper,
                    removedElsewhere: existing.removedElsewhere ?? item.removedElsewhere,
                    isInTheTrash: existing.isInTheTrash || item.isInTheTrash,
                    enclosingPackage: existing.enclosingPackage ?? item.enclosingPackage,
                    holdsDamagedSettings: existing.holdsDamagedSettings || item.holdsDamagedSettings
                )
            } else {
                byURL[item.url] = item
                order.append(item.url)
            }
        }

        for uninstallation in uninstallations {
            let reference = uninstallation.app.reference
            // A chosen app's bundle is that app's row, whatever another chosen app's scan says of it.
            for leftover in uninstallation.scan.leftovers
            where !chosenBundles.contains(PathPattern.comparablePath(of: leftover.url)) {
                add(Item(
                    url: leftover.url,
                    size: leftover.size,
                    kind: leftover.kind,
                    requiresPrivileges: leftover.requiresPrivileges,
                    apps: [reference],
                    match: leftover.match,
                    sharedWithOthers: leftover.match.sharedWith.filter { !chosen.contains($0) },
                    otherCopies: leftover.match.otherCopies.filter {
                        !chosenBundles.contains(PathPattern.comparablePath(of: $0))
                    },
                    isExcluded: leftover.match.heldBack == .holdsAnExclusion,
                    isKeptByMacOS: uninstallation.app.isSystemProtected,
                    isMeasured: leftover.isMeasured,
                    isBeyondTheHelper: leftover.match.heldBack == .beyondTheHelper,
                    removedElsewhere: uninstallation.removedElsewhere,
                    holdsDamagedSettings: leftover.holdsDamagedSettings
                ))
            }
            add(Item(
                url: uninstallation.app.url,
                size: uninstallation.appSize,
                kind: nil,
                requiresPrivileges: uninstallation.appRequiresPrivileges,
                apps: [reference],
                match: nil,
                sharedWithOthers: [],
                isExcluded: uninstallation.isExcluded,
                isKeptByMacOS: uninstallation.app.isSystemProtected,
                isMeasured: uninstallation.isAppMeasured,
                isBeyondTheHelper: uninstallation.isAppBeyondTheHelper,
                removedElsewhere: uninstallation.removedElsewhere,
                isInTheTrash: uninstallation.isAppInTheTrash,
                enclosingPackage: uninstallation.app.enclosingPackage
            ))
        }

        return order.compactMap { byURL[$0] }.sorted { lhs, rhs in
            if lhs.isApplication != rhs.isApplication { return rhs.isApplication }
            // What could not be measured first, as on an app's own page: it is most likely the biggest.
            if lhs.isMeasured != rhs.isMeasured { return !lhs.isMeasured }
            if lhs.size != rhs.size { return lhs.size > rhs.size }
            return lhs.url.path(percentEncoded: false) < rhs.url.path(percentEncoded: false)
        }
    }
}
