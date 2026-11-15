public import Foundation

/// What stays selected in File Search when a new search lists other files. What the new list holds stays selected
/// in it, and a selected file it leaves out stays selected apart, as the search that listed it found it, so it still
/// moves with the rest until the person deselects it. The page says how many there are.
public struct SearchSelection: Sendable {
    /// The selected files the list doesn't show.
    public private(set) var outside: [URL: FoundFile] = [:]

    public init() {}

    /// The selection once `files` is the list, `known` being the list before. A file that can't be selected, or that
    /// is gone from the disk, leaves it.
    public mutating func update(_ selected: Set<URL>, was known: [FoundFile], now files: [FoundFile]) -> Set<URL> {
        let listed = Dictionary(files.map { ($0.url, $0) }, uniquingKeysWith: { first, _ in first })
        var records = outside
        for file in known { records[file.url] = file }
        var kept: Set<URL> = []
        var apart: [URL: FoundFile] = [:]
        for url in selected {
            if let file = listed[url] {
                if !file.isLeftAlone { kept.insert(url) }
            } else if let file = records[url], !file.isLeftAlone, !url.isMissing {
                apart[url] = file
                kept.insert(url)
            }
        }
        outside = apart
        return kept
    }

    /// `selected` without the files kept apart, which are forgotten.
    public mutating func deselectOutside(from selected: Set<URL>) -> Set<URL> {
        defer { outside = [:] }
        return selected.subtracting(outside.keys)
    }

    /// What the list's Select menu works on: the files it shows, then the files kept apart, which Deselect All takes
    /// out too and the rest leaves selected.
    public func rows(showing files: [FoundFile], recommended: Set<URL>) -> SelectableRows<URL> {
        let apart = Array(outside.keys)
        return SelectableRows(
            rows: files.map(\.url) + apart,
            selectable: files.filter { !$0.isLeftAlone }.map(\.url) + apart,
            recommended: files.map(\.url).filter(recommended.contains) + apart
        )
    }

    /// Forgets the files kept apart that are no longer in `selected`.
    public mutating func forgetUnselected(_ selected: Set<URL>) {
        outside = outside.filter { selected.contains($0.key) }
    }

    /// Forgets `urls`, as when they are excluded or moved.
    public mutating func forget(_ urls: some Sequence<URL>) {
        for url in urls {
            outside[url] = nil
        }
    }
}
