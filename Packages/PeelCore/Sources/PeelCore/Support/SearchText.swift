public import Foundation

/// How every search field matches text. Case, accents and width are ignored, so full-width letters typed with a
/// Japanese, Chinese or Korean input method still match. The user's locale is tried first, then no locale: in
/// Turkish, `I` folds to `ı`, so `iina` would miss IINA, and the second pass finds it.
public enum SearchText {
    public static func matches(_ text: String, _ query: String, locale: Locale = .current) -> Bool {
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]
        return text.range(of: query, options: options, locale: locale) != nil
            || text.range(of: query, options: options) != nil
    }

    /// The items whose key holds `query`, in their order, worked out off the main actor for keys that are long, such
    /// as History's, where a removal's key names every item in it. Nil when the task that asked was canceled first, as
    /// it is when another key is typed.
    @concurrent
    public static func matching<Item: Identifiable & Sendable>(
        _ query: String, among items: [Item], keys: [Item.ID: String]
    ) async -> [Item]? where Item.ID: Sendable {
        var found: [Item] = []
        for item in items {
            if Task.isCancelled { return nil }
            if let key = keys[item.id], matches(key, query) {
                found.append(item)
            }
        }
        return found
    }
}

/// A list and what a search looks in for each of its items, read once: typing in a search field would otherwise
/// read every item again at each key.
public struct SearchableList<Item: Sendable>: Sendable {
    public let items: [Item]
    private let keys: [String]

    public init(_ items: [Item], key: (Item) -> String) {
        self.items = items
        keys = items.map(key)
    }

    /// The items whose key holds `query`, as `SearchText` compares; all of them for an empty query.
    public func matching(_ query: String) -> [Item] {
        guard !query.isEmpty else { return items }
        return zip(items, keys).filter { SearchText.matches($0.1, query) }.map(\.0)
    }
}
