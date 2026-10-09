public import Foundation

/// What a confirmation asks about: the selection as it was when the question appeared, and the sizes the scan
/// measured for it. The move takes exactly that, and History records those sizes.
public struct RemovalRequest: Sendable, Equatable {
    public let urls: Set<URL>
    /// The size of each item the scan measured. An item missing here was not measured.
    public let sizes: [URL: Int64]

    public init(urls: Set<URL>, sizes: [URL: Int64]) {
        self.urls = urls
        self.sizes = sizes
    }

    public var total: SizeTotal {
        SizeTotal(movingItemsAt: Dictionary(uniqueKeysWithValues: urls.map { ($0, sizes[$0]) }))
    }
}
