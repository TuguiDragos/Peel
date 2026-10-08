/// The rows of one list, for its Select All, Select Recommended and Deselect All: every row, those a click can
/// select, and those Peel recommends. Select All selects every row a click can select, and asks first about those
/// Peel doesn't recommend.
public struct SelectableRows<ID: Hashable> {
    public let rows: [ID]
    public let selectable: [ID]
    /// Never a row a click cannot select.
    public let recommended: [ID]

    public init(rows: [ID], selectable: [ID], recommended: [ID]) {
        self.rows = rows
        self.selectable = selectable
        self.recommended = recommended.filter(Set(selectable).contains)
    }

    public func isAllSelected(in selection: Set<ID>) -> Bool {
        selectable.allSatisfy(selection.contains)
    }

    public func isRecommendedSelected(in selection: Set<ID>) -> Bool {
        selection.intersection(rows) == Set(recommended)
    }

    public func isNoneSelected(in selection: Set<ID>) -> Bool {
        !rows.contains(where: selection.contains)
    }

    public func selectingAll(in selection: Set<ID>) -> Set<ID> {
        selection.union(selectable)
    }

    public func selectingRecommended(in selection: Set<ID>) -> Set<ID> {
        selection.subtracting(rows).union(recommended)
    }

    /// Takes out every row of the list, one a click can no longer select included.
    public func deselectingAll(in selection: Set<ID>) -> Set<ID> {
        selection.subtracting(rows)
    }

    /// What Select All would add that Peel does not recommend, which it asks about first.
    public func notRecommendedAdded(by selection: Set<ID>) -> [ID] {
        let recommended = Set(recommended)
        return selectable.filter { !recommended.contains($0) && !selection.contains($0) }
    }
}

/// The rows of every page a tool lists, for one Select menu over all of them.
public struct SelectablePages<Page: Hashable, ID: Hashable> {
    private let pages: [(page: Page, rows: SelectableRows<ID>)]
    /// Every page's rows as one list, a row that two pages share counted once.
    public let rows: SelectableRows<ID>

    public init(_ pages: [(page: Page, rows: SelectableRows<ID>)]) {
        self.pages = pages
        func once(_ ids: [ID]) -> [ID] {
            var seen = Set<ID>()
            return ids.filter { seen.insert($0).inserted }
        }
        rows = SelectableRows(
            rows: once(pages.flatMap { $0.rows.rows }),
            selectable: once(pages.flatMap { $0.rows.selectable }),
            recommended: once(pages.flatMap { $0.rows.recommended })
        )
    }

    /// The pages Select All reaches: those with a row a click can select.
    public var selectablePageCount: Int {
        pages.count { !$0.rows.selectable.isEmpty }
    }

    public func pages(selectedIn selection: Set<ID>) -> [Page] {
        pages.filter { $0.rows.rows.contains(where: selection.contains) }.map(\.page)
    }

    /// What of `selection` would move: a row only on pages not seen yet stays where it is (`CarriedSelection`).
    public func counted(_ selection: Set<ID>, seen: (Page) -> Bool) -> Set<ID> {
        let onSeenPages = Set(pages.filter { seen($0.page) }.flatMap { $0.rows.rows })
        return selection.subtracting(rows.rows.filter { !onSeenPages.contains($0) })
    }
}
