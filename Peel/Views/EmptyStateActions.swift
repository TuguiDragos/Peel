import SwiftUI

/// The buttons of an empty state: side by side when they fit the width they are given, otherwise one under another,
/// each as wide as its own title. An empty state lays its actions in one row that never wraps, so in a list column a
/// few buttons would run past both edges.
struct EmptyStateActions<Content: View>: View {
    @ViewBuilder let content: Content

    /// The gap an empty state leaves between the buttons of its own row.
    static var spacing: CGFloat { 6 }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Self.spacing) { content }
            VStack(spacing: Self.spacing) { Group { content }.fixedSize() }
        }
    }
}
