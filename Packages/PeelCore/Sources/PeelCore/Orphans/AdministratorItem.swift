public import Foundation

/// An item only an administrator can move, from a place the helper may not move it from. Orphaned Files lists these
/// apart, with how to remove them by hand.
public struct AdministratorItem: Sendable, Hashable, Identifiable {
    public let item: OrphanItem
    /// The apps it was found for, by name.
    public let apps: [String]

    public var id: URL { item.url }
}
