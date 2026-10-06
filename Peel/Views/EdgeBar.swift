import SwiftUI

extension View {
    /// A bar across the top or the foot of a scrolling page, such as a search field or a button with its note.
    /// macOS 27 draws a background across the page behind a bar even when nothing is under it, so there the bar
    /// takes room as an inset instead, with nothing drawn behind it.
    @ViewBuilder
    func edgeBar(_ edge: VerticalEdge, spacing: CGFloat? = nil, @ViewBuilder content: () -> some View) -> some View {
        if #available(macOS 27, *) {
            safeAreaInset(edge: edge, spacing: spacing ?? 0, content: content)
        } else {
            safeAreaBar(edge: edge, spacing: spacing, content: content)
        }
    }
}
