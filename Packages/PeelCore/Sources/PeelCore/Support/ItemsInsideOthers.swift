public import Foundation
internal import PeelPrivileged

/// The items of one list that sit inside another item of the same list, read from the names in their paths. Moving
/// that item takes them along, so a total counts them once.
public struct ItemsInsideOthers: Sendable {
    private let holders: [URL: URL]

    public init(_ urls: some Sequence<URL>) {
        let items = urls.map { (url: $0, names: PathComponents.of(PathPattern.comparablePath(of: $0))) }
        let byNames = Dictionary(items.map { ($0.names, $0.url) }) { first, _ in first }
        var holders: [URL: URL] = [:]
        for item in items {
            let holder = stride(from: item.names.count - 1, to: 0, by: -1).lazy
                .compactMap { byNames[Array(item.names.prefix($0))] }.first
            if let holder { holders[item.url] = holder }
        }
        self.holders = holders
    }

    /// The item of the list `url` sits inside, the nearest when several hold it, or nil when none does.
    public func holder(of url: URL) -> URL? {
        holders[url]
    }
}
