/// The rows of one list, for its Select All, Select Recommended and Deselect All: every row, those a click can
/// select, and those Peel recommends.
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

    /// Takes out every row of the list, one selected by hand that Select All would leave alone included.
    public func deselectingAll(in selection: Set<ID>) -> Set<ID> {
        selection.subtracting(rows)
    }

    /// What Select All would add that Peel does not recommend, which it asks about first.
    public func notRecommendedAdded(by selection: Set<ID>) -> [ID] {
        let recommended = Set(recommended)
        return selectable.filter { !recommended.contains($0) && !selection.contains($0) }
    }
}
