public import Foundation

/// What is selected on the pages of the storage tools, and what of it moves when Move to Trash is pressed on any
/// of them: each page the person has seen, one part to a page. A tool can select for the person on pages they
/// never opened (Developer selects the caches it recommends in every tool it lists), and what was never seen must
/// never be moved from another page, so a page counts only once it has been on screen.
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

        public init(page: Page, title: String, source: String, sourceKey: String?, sizes: [URL: Int64?]) {
            self.page = page
            self.title = title
            self.source = source
            self.sourceKey = sourceKey
            self.sizes = sizes
        }

        public var id: Page { page }
        public var count: Int { sizes.count }
        public var total: SizeTotal { SizeTotal(sizes.values) }

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
                return Part(page: part.page, title: part.title, source: part.source, sourceKey: part.sourceKey, sizes: sizes)
            }
        }
    }

    /// The pages seen so far, in the order they were first seen.
    private var seen: [Page] = []

    public init() {}

    public mutating func saw(_ page: Page) {
        if !seen.contains(page) { seen.append(page) }
    }

    public func hasSeen(_ page: Page) -> Bool {
        seen.contains(page)
    }

    /// The parts that move: those of `candidates` whose page was seen and has something selected, in the order of
    /// `tools`, which is the sidebar's, and within a tool in the order its pages were seen.
    public func parts(from candidates: [Part], order tools: [String]) -> [Part] {
        func place(_ part: Part) -> (Int, Int) {
            (tools.firstIndex(of: part.page.tool) ?? tools.count, seen.firstIndex(of: part.page) ?? seen.count)
        }
        return candidates
            .filter { !$0.sizes.isEmpty && seen.contains($0.page) }
            .sorted { place($0) < place($1) }
    }

    /// Moves each part in turn with `move`, which runs the part's own tool with its own checks and answers nil when
    /// the tool kept the whole part (an app it waits for was opened, for example). Every part is tried, whatever
    /// came of the ones before.
    public static func pass(_ parts: [Part], move: (Part) async -> TrashResult?) async -> Pass {
        var pass = Pass()
        for part in parts {
            if let result = await move(part) {
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

    /// The tools the parts come from, each once, in the parts' order.
    public var tools: [String] {
        var tools: [String] = []
        for part in self where !tools.contains(part.page.tool) {
            tools.append(part.page.tool)
        }
        return tools
    }
}
