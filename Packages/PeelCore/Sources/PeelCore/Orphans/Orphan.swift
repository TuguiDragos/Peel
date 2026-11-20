public import Foundation
internal import PeelPrivileged

public struct OrphanItem: Sendable, Hashable, Identifiable {
    public let url: URL
    public let kind: SearchLocation.Kind
    /// The space the item takes on disk, or nil when it could not be measured in time. Nil does not mean empty.
    public let size: Int64?
    /// When the item or anything inside it was last modified. Only its own date if it was not measured in time.
    public let modificationDate: Date?
    public let requiresPrivileges: Bool
    /// Why the item is left for the user to choose by hand, or nil. Select All asks before it selects it, and `peel
    /// orphans --remove` leaves it where it is.
    public var heldBack: HoldBack?
    /// The bundle identifier of the app that left, when the item bears its name and nothing else ties the two.
    public var namedAfter: String?
    /// True for a preference file that is no property list (`PreferenceFile.isDamaged`).
    public var holdsDamagedSettings = false
    /// For a copy macOS keeps of a system extension, the path of the app its record says it was installed for, when
    /// that app is gone.
    public var installedFor: String?
    /// For a folder the gone app's own product file named for its data, or its maker documents, that folder.
    public var productFolder: ProductFolder?
    /// True when only an administrator can move it, from where the helper can't move it, and nothing else
    /// holds it back.
    public var isLeftForAnAdministrator = false
    /// Where it leads in the end, when it is a symbolic link: moving it moves the link, not what is there.
    public var leadsTo: URL? = nil
    /// The folder a scan walked down from to find it, into real folders alone. Nil for a record of an earlier
    /// uninstall.
    public var foundBelow: URL? = nil
    public var scanIdentity: ScanIdentity? = nil

    /// Why the item cannot be selected at all: `RemovalGuard` or the helper would refuse it.
    public var leftAlone: HoldBack? {
        heldBack?.cannotBeMoved == true ? heldBack : nil
    }

    public var id: URL { url }

    public func isLocked(canUseHelper: Bool) -> Bool {
        requiresPrivileges && leftAlone == nil && !canUseHelper
    }
}

public struct OrphanGroup: Sendable, Hashable, Identifiable {
    public let identifier: String
    public let items: [OrphanItem]
    /// The app these files belonged to, when Peel saw it installed before it went away.
    public var rememberedApp: RememberedApp?
    /// How sure Peel is that nothing uses these files anymore. It changes how the row reads, where it is listed
    /// and whether Peel recommends the files, never what is selected: orphaned files are never selected for the user.
    public var confidence = OrphanConfidence(level: .likely, reasons: [.nothingClaimsIt])
    public var makersUninstaller: MakersUninstaller?

    public var id: String { identifier }

    /// The app's name if Peel remembers it, and the identifier otherwise.
    public var title: String {
        rememberedApp?.name ?? identifier
    }

    public var total: SizeTotal {
        SizeTotal(items.map(\.size))
    }

    /// What moving the group could free now, which its "to remove" says: the items a checkbox can select, as the bar
    /// beside it counts them, so what Peel leaves alone, and what only the helper moves while it can't, aren't counted.
    public func movable(canUseHelper: Bool) -> SizeTotal {
        let selectable = Set(selectableRows(canUseHelper: canUseHelper).selectable)
        return SizeTotal(items.filter { selectable.contains($0.url) }.map(\.size))
    }

    /// The size a row of the list shows, as the page's total does: none while nothing could move now.
    public func figure(canUseHelper: Bool) -> SizeTotal? {
        let movable = movable(canUseHelper: canUseHelper)
        return movable.isNothing ? nil : movable
    }

    public var lastModified: Date? {
        items.compactMap(\.modificationDate).max()
    }

    /// The gone app macOS's record says these system extension copies were installed for, when every item names it.
    public var installedFor: String? {
        guard let app = items.first?.installedFor, items.allSatisfy({ $0.installedFor == app }) else { return nil }
        return app
    }

    /// True when nothing in the group can be moved, every item being left alone.
    public var isLeftAlone: Bool {
        items.allSatisfy { $0.leftAlone != nil }
    }

    /// The reason every item is left alone for, when they all share one.
    public var sharedReason: HoldBack? {
        guard let reason = items.first?.leftAlone, items.allSatisfy({ $0.leftAlone == reason }) else { return nil }
        return reason
    }

    /// Peel recommends no row it held back, and nothing in a group something may still use: such rows wait to be
    /// chosen by hand, as Review Before Removing does on an app's page.
    public func selectableRows(canUseHelper: Bool) -> SelectableRows<URL> {
        let unlocked = items.filter { !$0.isLocked(canUseHelper: canUseHelper) }
        return SelectableRows(
            rows: items.map(\.url),
            selectable: unlocked.filter { $0.leftAlone == nil }.map(\.url),
            recommended: confidence.level == .unsure ? [] : unlocked.filter { $0.heldBack == nil }.map(\.url)
        )
    }
}

public struct OrphanScan: Sendable {
    public let groups: [OrphanGroup]
    public let unreadableLocations: [SearchLocation]
    /// True when macOS's privacy protection, not ordinary permissions, kept Peel out of one of `unreadableLocations`,
    /// so Full Disk Access would open it.
    public var needsFullDiskAccess = false
    /// The folders whose folders the search inside did not all reach, at its limit, so an orphaned file may be in
    /// one it did not reach.
    public var cutShortLocations: [SearchLocation] = []
    public var crowdedFolders: [CrowdedFolder] = []
    /// What only an administrator can move, listed apart from the groups.
    public let forAnAdministrator: [AdministratorItem]
    /// Apps macOS knows on another disk that claimed something: Peel remembers them for when that disk isn't connected.
    public var appsOnOtherDisks: [InstalledApp] = []
    /// True when this Mac has other accounts and something listed is outside the folders that are this account's
    /// alone: an app one of them keeps in its own Applications folder is out of Peel's sight, and what it left in
    /// `/Library` looks orphaned.
    public let otherAccountsMayOwn: Bool
    /// The folders that are this account's alone on a Mac that has other accounts, and nil on a Mac with none.
    private let foldersOfThisAccountAlone: [URL]?

    /// `otherAccountsMayOwn` is worked out here, once, from what the scan lists, so a filtered scan answers for what
    /// it kept.
    init(
        groups: [OrphanGroup], unreadableLocations: [SearchLocation], needsFullDiskAccess: Bool = false,
        cutShortLocations: [SearchLocation] = [], crowdedFolders: [CrowdedFolder] = [],
        forAnAdministrator: [AdministratorItem] = [], appsOnOtherDisks: [InstalledApp] = [],
        foldersOfThisAccountAlone: [URL]? = nil
    ) {
        self.groups = groups
        self.unreadableLocations = unreadableLocations
        self.needsFullDiskAccess = needsFullDiskAccess
        self.cutShortLocations = cutShortLocations
        self.crowdedFolders = crowdedFolders
        self.forAnAdministrator = forAnAdministrator
        self.appsOnOtherDisks = appsOnOtherDisks
        self.foldersOfThisAccountAlone = foldersOfThisAccountAlone
        otherAccountsMayOwn = foldersOfThisAccountAlone.map { folders in
            let own = folders.map { PathComponents.of($0.path(percentEncoded: false)) }
            let isElsewhere = { (url: URL) in
                let names = PathComponents.of(url.path(percentEncoded: false))
                return !own.contains { names.starts(with: $0) }
            }
            return groups.contains { $0.items.contains { isElsewhere($0.url) } }
                || forAnAdministrator.contains { isElsewhere($0.item.url) }
        } ?? false
    }

    public func group(listing url: URL) -> OrphanGroup? {
        let path = PathPattern.comparablePath(of: url)
        return groups.first { $0.items.contains { PathPattern.comparablePath(of: $0.url) == path } }
    }

    /// The group `identifier` falls in, as `OrphanScanner.group` gathers them.
    public func group(holding identifier: String) -> OrphanGroup? {
        groups.first { OrphanScanner.isInAGroup(identifier, among: [$0.identifier.lowercased()]) }
    }

    /// The same scan without the group `id`, as when the person said it belongs to an app.
    public func without(_ id: OrphanGroup.ID) -> OrphanScan {
        keeping { $0.id != id }
    }

    /// The same scan without the groups `owners` give to an app of `installedApps` or a tool of `tools`
    /// (`OrphanOwners.given`), for a scan that ran while the person gave one away.
    public func leavingOut(
        given owners: [String: OrphanOwner], installedApps: [InstalledApp], tools: InstalledTools
    ) -> OrphanScan {
        let here = Set(installedApps.compactMap { $0.bundleIdentifier?.lowercased() })
        let given = OrphanOwners.given(owners, apps: here, tools: tools)
        return keeping { !OrphanScanner.isInAGroup($0.identifier, among: given) }
    }

    private func keeping(_ isKept: (OrphanGroup) -> Bool) -> OrphanScan {
        OrphanScan(
            groups: groups.filter(isKept), unreadableLocations: unreadableLocations,
            needsFullDiskAccess: needsFullDiskAccess, cutShortLocations: cutShortLocations,
            crowdedFolders: crowdedFolders, forAnAdministrator: forAnAdministrator, appsOnOtherDisks: appsOnOtherDisks,
            foldersOfThisAccountAlone: foldersOfThisAccountAlone
        )
    }
}

extension OrphanItem: FoundByAScan {}
