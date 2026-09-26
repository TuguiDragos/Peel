public import Foundation

/// What stays selected on a page when what it lists changes: a scan finds other items, or the helper comes or goes.
///
/// An item the person could already choose keeps its checkbox as they left it, so nothing they deselected comes
/// back. Peel's suggestion applies only to an item they could not choose until now: one new to the page, or one
/// that could not be selected before. An item leaves the selection when it is gone, when it can no longer be
/// selected, or when Peel had suggested it and no longer does.
public struct KeptSelection: Sendable {
    /// Each item the person could choose after the last update, and whether Peel suggested it.
    private var offered: [URL: Bool] = [:]
    /// The selection the last update made, so a page can tell whether the person has changed it since.
    public private(set) var made: Set<URL> = []

    public init() {}

    /// The selection that follows `selected` now that the page offers `selectable` and suggests `suggested`.
    public mutating func update(_ selected: Set<URL>, selectable: Set<URL>, suggested: Set<URL>) -> Set<URL> {
        made = selectable.filter { url in
            guard let wasSuggested = offered[url] else { return suggested.contains(url) }
            return selected.contains(url) && (suggested.contains(url) || !wasSuggested)
        }
        offered = Dictionary(uniqueKeysWithValues: selectable.map { ($0, suggested.contains($0)) })
        return made
    }

    /// Forgets every choice, so the next update is Peel's suggestion alone.
    public mutating func startOver() {
        offered = [:]
    }
}
