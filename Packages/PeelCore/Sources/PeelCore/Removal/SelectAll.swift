/// What a section's Select All and Deselect All do to the selection.
public enum SelectAll {
    public static func isAllSelected<ID: Hashable>(_ selectable: [ID], in selection: Set<ID>) -> Bool {
        selectable.allSatisfy(selection.contains)
    }

    /// Select All adds the rows that can be selected. Deselect All takes out every row of the section, a row
    /// selected by hand that Select All leaves alone included.
    public static func toggled<ID: Hashable>(_ selection: Set<ID>, selectable: [ID], rows: [ID]) -> Set<ID> {
        isAllSelected(selectable, in: selection) ? selection.subtracting(rows) : selection.union(selectable)
    }
}
