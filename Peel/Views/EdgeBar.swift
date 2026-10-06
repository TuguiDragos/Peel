import SwiftUI

extension View {
    /// A bar across the top or the foot of a scrolling page, such as a search field or a button with its note.
    /// What scrolls under a bar at the top blurs, as macOS draws it. At the foot, macOS 27 draws a background across
    /// the page behind a bar even when nothing is under it, so there a bar at the foot takes room as an inset
    /// instead, with nothing drawn behind it.
    @ViewBuilder
    func edgeBar(_ edge: VerticalEdge, spacing: CGFloat? = nil, @ViewBuilder content: () -> some View) -> some View {
        if #available(macOS 27, *) {
            if edge == .top {
                TopBar(page: self, spacing: spacing, bar: content())
            } else {
                safeAreaInset(edge: edge, spacing: spacing ?? 0, content: content)
            }
        } else {
            safeAreaBar(edge: edge, spacing: spacing, content: content)
        }
    }
}

/// A bar at the top of a page on macOS 27, put on the page inside a view of its own: there, a bar put directly on a
/// case of a `switch` can crash SwiftUI when that case is chosen.
@available(macOS 27, *)
private struct TopBar<Page: View, Bar: View>: View {
    let page: Page
    let spacing: CGFloat?
    let bar: Bar

    var body: some View {
        page.safeAreaBar(edge: .top, spacing: spacing) { bar }
    }
}
