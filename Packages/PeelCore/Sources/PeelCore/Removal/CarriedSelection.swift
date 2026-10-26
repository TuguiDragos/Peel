public import Foundation

/// What is selected on the pages of the storage tools, and what of it moves when Move to Trash is pressed on any
/// of them: each page the person has seen, one part to a page. What was never seen must never be moved from
/// another page, so a page counts only once it has been on screen.
public struct CarriedSelection: Sendable {
    /// One page of a tool: `tool` names the tool, and `scope` the page within it, such as a developer tool, a
    /// project, or a kind of installer. It is empty for a tool that is one page.
    public struct Page: Sendable, Hashable {
        public let tool: String
        public let scope: String

        public init(tool: String, scope: String) {
            self.tool = tool
            self.scope = scope
        }
    }

    /// What one page has selected: its items with the sizes the page measured, nil where it could not, the page's
    /// title as the page shows it, and the source History names them by.
    public struct Part: Sendable, Hashable, Identifiable {
        public let page: Page
        public let title: String
        public let source: String
        public let sourceKey: String?
        public let sizes: [URL: Int64?]
        /// The tool checks right before its move what the parts before it left, as Duplicates does for the copy it
        /// keeps, so it moves after every other part.
        public let movesLast: Bool

        public init(
            page: Page, title: String, source: String, sourceKey: String?, sizes: [URL: Int64?], movesLast: Bool = false
        ) {
            self.page = page
            self.title = title
            self.source = source
            self.sourceKey = sourceKey
            self.sizes = sizes
            self.movesLast = movesLast
        }

        public var id: Page { page }
        public var count: Int { sizes.count }
        public var total: SizeTotal { SizeTotal(sizes.values) }

        func keeping(_ sizes: [URL: Int64?]) -> Part {
            Part(page: page, title: title, source: source, sourceKey: sourceKey, sizes: sizes, movesLast: movesLast)
        }

        /// The items of this part `result` neither moved, refused, nor took along in a folder it moved.
        func unaccounted(by result: TrashResult) -> [URL] {
            let moved = Set(result.trashed.map { CarriedSelection.writtenPath(of: $0.originalURL) })
            let refused = Set(result.failures.map { CarriedSelection.writtenPath(of: $0.url) })
            return sizes.keys.filter { url in
                let path = CarriedSelection.writtenPath(of: url)
                return !moved.contains(path) && !refused.contains(path)
                    && !CarriedSelection.folders(above: path).contains(where: moved.contains)
            }
            .sorted { $0.path(percentEncoded: false) < $1.path(percentEncoded: false) }
        }

        public var removalPart: RemovalPart {
            RemovalPart(source: source, sourceKey: sourceKey, tool: page.tool)
        }

        /// The sizes History records for the part: those its page measured.
        public var measuredSizes: [URL: Int64] {
            [URL: Int64](measured: sizes.lazy.map { ($0.key, $0.value) })
        }
    }

    /// What a pass did with each part: moved, with what came of it, or kept whole by its tool.
    public struct Pass: Sendable {
        public var moved: [(part: Part, result: TrashResult)] = []
        public var kept: [Part] = []

        /// Every item the moved parts moved, and every one their tools refused.
        public var result: TrashResult {
            TrashResult(trashed: moved.flatMap(\.result.trashed), failures: moved.flatMap(\.result.failures))
        }

        /// What each part's tool refused for the item itself, which would be refused again as it is now, so it
        /// leaves the selection.
        public var refused: [Part] {
            moved.compactMap { part, result in
                let urls = Set(result.failures.filter(\.reason.isAboutTheItem).map(\.url))
                let sizes = part.sizes.filter { urls.contains($0.key) }
                guard !sizes.isEmpty else { return nil }
                return part.keeping(sizes)
            }
        }
    }

    /// The pages seen so far, in the order they were first seen.
    private var seen: [Page] = []

    /// The path as written, without a trailing slash: `comparablePath` reads the disk, too slow for the bar.
    static func writtenPath(of url: URL) -> Substring {
        let path = url.path(percentEncoded: false)
        return path.count > 1 && path.hasSuffix("/") ? path.dropLast() : Substring(path)
    }

    /// The folders above `path`, split at the slash byte: a `Character` joins a slash and a combining mark.
    static func folders(above path: Substring) -> some Sequence<Substring> {
        path.utf8.indices.lazy.filter { $0 != path.startIndex && path.utf8[$0] == UInt8(ascii: "/") }.map { path[..<$0] }
    }

    public init() {}

    public mutating func saw(_ page: Page) {
        if !seen.contains(page) { seen.append(page) }
    }

    public func hasSeen(_ page: Page) -> Bool {
        seen.contains(page)
    }

    /// The parts that move: those of `candidates` whose page was seen and has something selected, in the order of
    /// `tools`, which is the sidebar's, and within a tool in the order its pages were seen, a part that moves last
    /// after all of them.
    public func parts(from candidates: [Part], order tools: [String], asking page: Page? = nil) -> [Part] {
        func place(_ part: Part) -> (Int, Int, Int) {
            (part.movesLast ? 1 : 0, tools.firstIndex(of: part.page.tool) ?? tools.count,
             seen.firstIndex(of: part.page) ?? seen.count)
        }
        let parts = candidates.filter { !$0.sizes.isEmpty && seen.contains($0.page) }.sorted { place($0) < place($1) }
        return Self.eachItemOnce(in: parts, asking: page)
    }

    /// Each item moves once: one inside a folder another part holds goes with that folder, one two parts hold stays in
    /// the asking page's part or else the first. One page's own selection is left as its tool made it.
    private static func eachItemOnce(in parts: [Part], asking page: Page?) -> [Part] {
        guard parts.count > 1 else { return parts }
        let paths = parts.map { part in part.sizes.keys.map { (url: $0, path: writtenPath(of: $0)) } }
        var holder = [Substring: Int](minimumCapacity: paths.reduce(0) { $0 + $1.count })
        let asking = parts.indices.filter { parts[$0].page == page }
        // Written last to first, so a path two parts share is left to the first.
        for index in (asking + parts.indices.filter { !asking.contains($0) }).reversed() {
            for (_, path) in paths[index] {
                holder[path] = index
            }
        }
        var above = FolderHolders(holder: holder)
        return parts.indices.compactMap { index in
            let kept = paths[index].filter { _, path in
                holder[path] == index && above.noPartBut(index, holdsAFolderAbove: path)
            }
            guard kept.count < parts[index].sizes.count else { return parts[index] }
            let urls = Set(kept.map(\.url))
            return kept.isEmpty ? nil : parts[index].keeping(parts[index].sizes.filter { urls.contains($0.key) })
        }
    }

    /// Which parts hold the folders above a path, worked out once per folder.
    private struct FolderHolders {
        private enum Holders {
            case none, one(Int), several
        }

        let holder: [Substring: Int]
        private var known: [Substring: Holders] = [:]

        init(holder: [Substring: Int]) {
            self.holder = holder
        }

        mutating func noPartBut(_ index: Int, holdsAFolderAbove path: Substring) -> Bool {
            switch holders(above: path) {
            case .none: true
            case .one(let holder): holder == index
            case .several: false
            }
        }

        private mutating func holders(above path: Substring) -> Holders {
            guard let slash = path.utf8.lastIndex(of: UInt8(ascii: "/")), slash != path.startIndex else { return .none }
            let folder = path[..<slash]
            if let holders = known[folder] { return holders }
            var holders = holders(above: folder)
            switch (holders, holder[folder]) {
            case (.none, let index?): holders = .one(index)
            case (.one(let other), let index?) where other != index: holders = .several
            default: break
            }
            known[folder] = holders
            return holders
        }
    }

    /// Moves each part in turn with `move`, which runs the part's own tool with its own checks and answers nil when
    /// the tool kept the whole part (an app it waits for was opened, for example). Every part is tried, whatever
    /// came of the ones before.
    public static func pass(_ parts: [Part], move: (Part) async -> TrashResult?) async -> Pass {
        var pass = Pass()
        for part in parts {
            if var result = await move(part) {
                // A tool moves what its page lists and selects now, so what changed since the question stays.
                result.failures += part.unaccounted(by: result).map { TrashFailure(url: $0, reason: .changedSinceScan) }
                pass.moved.append((part, result))
            } else {
                pass.kept.append(part)
            }
        }
        return pass
    }
}

extension Sequence where Element == CarriedSelection.Part {
    public var itemCount: Int { reduce(0) { $0 + $1.count } }
    public var total: SizeTotal { SizeTotal(flatMap(\.sizes.values)) }

    /// The parts holding an item in `moved` or inside a folder in it, each with only those items.
    public func holding(_ moved: [URL]) -> [CarriedSelection.Part] {
        let gone = Set(moved.map(CarriedSelection.writtenPath(of:)))
        return compactMap { part in
            let sizes = part.sizes.filter { url, _ in
                let path = CarriedSelection.writtenPath(of: url)
                return gone.contains(path) || CarriedSelection.folders(above: path).contains(where: gone.contains)
            }
            return sizes.isEmpty ? nil : part.keeping(sizes)
        }
    }

    /// The tools the parts come from, each once, in the parts' order.
    public var tools: [String] {
        var tools: [String] = []
        for part in self where !tools.contains(part.page.tool) {
            tools.append(part.page.tool)
        }
        return tools
    }
}
