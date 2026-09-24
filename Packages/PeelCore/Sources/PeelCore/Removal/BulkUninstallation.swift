public import Foundation

/// An uninstall of several apps at once. Each file is listed once, and a file shared only among the chosen
/// apps is safe to remove, since all of them are going.
public struct BulkUninstallation: Sendable {
    public struct Item: Sendable, Hashable, Identifiable {
        public let url: URL
        public let size: Int64
        public let kind: SearchLocation.Kind?
        public let requiresPrivileges: Bool
        /// The bundle identifiers of the chosen apps this item belongs to.
        public let apps: [String]
        public let match: LeftoverMatch?
        /// The bundle identifiers of apps outside the selection that also claim this item.
        public let sharedWithOthers: [String]
        /// An excluded app, or an item with something excluded inside. Shown, never selected, never moved.
        public var isExcluded = false
        /// An app macOS protects, or an item found for one. The app stays, so none of it is a leftover to select.
        public var isKeptByMacOS = false
        /// False when the size could not be measured, so `size` is unknown rather than zero.
        public var isMeasured = true
        /// Needs administrator rights, and the helper may not move it. Shown, never selected, never moved.
        public var isBeyondTheHelper = false

        public var id: URL { url }
        public var isApplication: Bool { match == nil }
        public var isRecommended: Bool {
            guard !isExcluded, !isKeptByMacOS, !isBeyondTheHelper else { return false }
            guard let match else { return true }
            return sharedWithOthers.isEmpty && match.confidence >= .likely && match.heldBack == nil
        }
    }

    public let uninstallations: [Uninstallation]
    public let items: [Item]

    public var apps: [InstalledApp] { uninstallations.map(\.app) }
    /// The size of what could be moved, counted by the same rule as an app's own page: nothing the user
    /// excluded, no app macOS protects, and no row that can never be moved. An unmeasured row is never counted
    /// as zero: it makes the total incomplete.
    public var total: SizeTotal {
        SizeTotal(items
            .filter { !$0.isExcluded && !($0.isApplication && $0.isKeptByMacOS) && !$0.isBeyondTheHelper && $0.match?.heldBack?.cannotBeMoved != true }
            .map { $0.isMeasured ? $0.size : nil })
    }
    public var unreadableLocations: [SearchLocation] {
        Array(Set(uninstallations.flatMap { $0.scan.unreadableLocations })).sorted { $0.url.path(percentEncoded: false) < $1.url.path(percentEncoded: false) }
    }

    public init(uninstallations: [Uninstallation]) {
        self.uninstallations = uninstallations
        items = Self.merge(uninstallations)
    }

    @concurrent
    public static func prepare(
        _ apps: [InstalledApp],
        installedApps: [InstalledApp],
        exclusions: Exclusions = .none,
        casks: [HomebrewPackage] = [],
        receipts: Set<String> = [],
        environment: SearchEnvironment = .current
    ) async -> BulkUninstallation {
        var prepared: [Uninstallation] = []
        for app in apps where !Task.isCancelled {
            prepared.append(await Uninstallation.prepare(app, installedApps: installedApps, exclusions: exclusions, casks: casks, receipts: receipts, environment: environment))
        }
        return BulkUninstallation(uninstallations: prepared)
    }

    /// What is selected for the user at first. Nothing of an app that would stay, as on its own page, and that
    /// includes what it shares with another chosen app: it goes on using it.
    public func suggestedSelection(canUseHelper: Bool) -> Set<URL> {
        let staying = Set(uninstallations.filter { $0.appStays(canUseHelper: canUseHelper) }.map(\.app.bundleIdentifier))
        return Set(items.filter { item in
            item.isRecommended && (canUseHelper || !item.requiresPrivileges) && !item.apps.contains(where: staying.contains)
        }.map(\.url))
    }

    public var privilegedURLs: Set<URL> {
        Set(items.filter { $0.requiresPrivileges && !$0.isExcluded && !$0.isBeyondTheHelper && !($0.isApplication && $0.isKeptByMacOS) }.map(\.url))
    }

    /// Returns the selection in the order it is moved: leftovers first, then the apps. Excluded items are left out.
    public func removalOrder(of selection: Set<URL>) -> [URL] {
        let movable = items.filter { !$0.isExcluded && selection.contains($0.url) }
        return movable.filter { !$0.isApplication }.map(\.url) + movable.filter(\.isApplication).map(\.url)
    }

    static func merge(_ uninstallations: [Uninstallation]) -> [Item] {
        let chosen = Set(uninstallations.map(\.app.bundleIdentifier))
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
                    match: existing.match.flatMap { known in item.match.map(known.combined) } ?? existing.match ?? item.match,
                    sharedWithOthers: existing.sharedWithOthers.filter(item.sharedWithOthers.contains),
                    isExcluded: existing.isExcluded || item.isExcluded,
                    isKeptByMacOS: existing.isKeptByMacOS || item.isKeptByMacOS,
                    isMeasured: existing.isMeasured || item.isMeasured,
                    isBeyondTheHelper: existing.isBeyondTheHelper || item.isBeyondTheHelper
                )
            } else {
                byURL[item.url] = item
                order.append(item.url)
            }
        }

        for uninstallation in uninstallations {
            let identifier = uninstallation.app.bundleIdentifier
            for leftover in uninstallation.scan.leftovers {
                add(Item(
                    url: leftover.url,
                    size: leftover.size,
                    kind: leftover.kind,
                    requiresPrivileges: leftover.requiresPrivileges,
                    apps: [identifier],
                    match: leftover.match,
                    sharedWithOthers: leftover.match.sharedWith.filter { !chosen.contains($0) },
                    isExcluded: leftover.match.heldBack == .holdsAnExclusion,
                    isKeptByMacOS: uninstallation.app.isSystemProtected,
                    isMeasured: leftover.isMeasured,
                    isBeyondTheHelper: leftover.match.heldBack == .beyondTheHelper
                ))
            }
            add(Item(
                url: uninstallation.app.url,
                size: uninstallation.appSize,
                kind: nil,
                requiresPrivileges: uninstallation.appRequiresPrivileges,
                apps: [identifier],
                match: nil,
                sharedWithOthers: [],
                isExcluded: uninstallation.isExcluded,
                isKeptByMacOS: uninstallation.app.isSystemProtected,
                isMeasured: uninstallation.isAppMeasured,
                isBeyondTheHelper: uninstallation.isAppBeyondTheHelper
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
