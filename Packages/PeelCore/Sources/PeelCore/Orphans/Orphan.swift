public import Foundation

public struct OrphanItem: Sendable, Hashable, Identifiable {
    public let url: URL
    public let kind: SearchLocation.Kind
    /// The space the item takes on disk, or nil when it could not be measured in time. Nil does not mean empty.
    public let size: Int64?
    /// When the item or anything inside it was last modified. Only its own date if it was not measured in time.
    public let modificationDate: Date?
    public let requiresPrivileges: Bool
    /// Why the item is left for the user to choose by hand, or nil. Select All passes it by, and `peel orphans
    /// --remove` leaves it where it is.
    public var heldBack: HoldBack?
    /// The bundle identifier of the app that left, when the item bears its name and nothing else ties the two.
    public var namedAfter: String?
    /// True for a preference file that is no property list (`PreferenceFile.isDamaged`).
    public var holdsDamagedSettings = false

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

    public var id: String { identifier }

    /// The app's name if Peel remembers it, and the identifier otherwise.
    public var title: String {
        rememberedApp?.name ?? identifier
    }

    public var total: SizeTotal {
        SizeTotal(items.map(\.size))
    }

    /// What moving the group could free: items Peel leaves alone are listed but not counted, as on an app's page.
    public var movable: SizeTotal {
        SizeTotal(items.filter { $0.leftAlone == nil }.map(\.size))
    }

    public var lastModified: Date? {
        items.compactMap(\.modificationDate).max()
    }

    /// Peel recommends no row it held back, and nothing in a group something may still use: such rows wait to be
    /// chosen by hand, as Review Before Removing does on an app's page.
    public func selectableRows(canUseHelper: Bool) -> SelectableRows<URL> {
        let unlocked = items.filter { !$0.isLocked(canUseHelper: canUseHelper) }
        return SelectableRows(
            rows: items.map(\.url),
            selectable: unlocked.filter { $0.leftAlone == nil }.map(\.url),
            recommended: confidence.level == .unsure ? [] : unlocked.filter { $0.heldBack == nil }.map(\.url),
            leftToTheClick: items.filter { $0.heldBack?.isLeftToTheClick == true }.map(\.url)
        )
    }
}

public struct OrphanScan: Sendable {
    public let groups: [OrphanGroup]
    public let unreadableLocations: [SearchLocation]
    /// True when macOS's privacy protection, not ordinary permissions, kept Peel out of one of `unreadableLocations`,
    /// so Full Disk Access would open it.
    public var needsFullDiskAccess = false
    /// The places with more folders inside than Peel looks into (`NestedSearch.folderLimit`), so an orphaned file
    /// may be in one it did not reach.
    public var cutShortLocations: [SearchLocation] = []

    /// The same scan without the group `id`, as when the person said it belongs to an app.
    public func without(_ id: OrphanGroup.ID) -> OrphanScan {
        OrphanScan(
            groups: groups.filter { $0.id != id }, unreadableLocations: unreadableLocations,
            needsFullDiskAccess: needsFullDiskAccess, cutShortLocations: cutShortLocations
        )
    }
}
