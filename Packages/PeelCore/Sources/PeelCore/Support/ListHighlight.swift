/// Which row of a list the arrow keys leave highlighted, while the focus stays in the search field above it.
public enum ListHighlight {
    public static func moved<ID: Equatable>(from current: ID?, by step: Int, among rows: [ID]) -> ID? {
        guard !rows.isEmpty else { return nil }
        guard let current, let index = rows.firstIndex(of: current) else {
            return step > 0 ? rows.first : rows.last
        }
        return rows[min(max(index + step, 0), rows.count - 1)]
    }
}
