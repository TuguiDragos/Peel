public import Foundation
internal import PeelPrivileged

/// Which items of a list sit inside another item of the same list.
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

    /// The nearest listed item `url` sits inside, or nil.
    public func holder(of url: URL) -> URL? {
        holders[url]
    }
}
