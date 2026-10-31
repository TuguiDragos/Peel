import SwiftUI

/// A list section's header: the heading at one end, and the count and the section's buttons at the other. A
/// macOS section header limits its children to one line, so when everything doesn't fit, the count is dropped
/// first, and then the heading wraps to a second line. The buttons always stay: nothing else on the page does
/// what Select All or Upgrade All does.
struct SectionHeaderLine<Heading: View, Count: View, Actions: View>: View {
    @ViewBuilder let heading: Heading
    @ViewBuilder let count: Count
    @ViewBuilder let actions: Actions

    var body: some View {
        // Each part is measured once: on macOS 26 every sheet or alert measures each header again, and a `ViewThatFits`
        // of whole lines would measure the heading's note and the buttons once per line.
        SectionHeaderLayout {
            HStack(spacing: SectionHeaderLayout.spacing) { heading }
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            // A count left out is gone, from VoiceOver too, rather than drawn at no width.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: SectionHeaderLayout.spacing) { count }
                Color.clear.frame(width: 0, height: 0)
            }
            HStack(spacing: SectionHeaderLayout.spacing) { actions }
        }
    }
}

extension SectionHeaderLine where Count == EmptyView {
    init(@ViewBuilder heading: () -> Heading, @ViewBuilder actions: () -> Actions) {
        self.init(heading: heading, count: { EmptyView() }, actions: actions)
    }
}

/// The heading, then the count and the buttons at the far end, centered on one line, with the room an eight point
/// spacer leaves between them. The buttons keep their whole width: with too little room the count is left out, and
/// then the heading wraps.
private struct SectionHeaderLayout: Layout {
    static let spacing: CGFloat = 8

    private struct Line {
        var heading: CGSize
        var showsCount: Bool
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? lineWidth(
            heading: subviews[0].sizeThatFits(.unspecified).width, trailing: trailing(subviews, showingCount: true)
        )
        let line = line(in: width, subviews: subviews)
        let count = line.showsCount ? subviews[1].sizeThatFits(.unspecified).height : 0
        let actions = subviews[2].sizeThatFits(.unspecified).height
        return CGSize(width: width, height: max(line.heading.height, count, actions))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let line = line(in: bounds.width, subviews: subviews)
        let count = line.showsCount ? subviews[1].sizeThatFits(.unspecified) : .zero
        let actions = subviews[2].sizeThatFits(.unspecified)
        func place(_ index: Int, at x: CGFloat, _ size: CGSize) {
            subviews[index].place(at: CGPoint(x: x, y: bounds.midY), anchor: .leading, proposal: ProposedViewSize(size))
        }
        place(0, at: bounds.minX, line.heading)
        place(2, at: bounds.maxX - actions.width, actions)
        place(1, at: bounds.maxX - actions.width - (actions.width > 0 ? Self.spacing : 0) - count.width, count)
    }

    /// What the line shows in `width`: everything, everything but the count, or the heading wrapped to the room left.
    private func line(in width: CGFloat, subviews: Subviews) -> Line {
        let heading = subviews[0].sizeThatFits(.unspecified)
        if lineWidth(heading: heading.width, trailing: trailing(subviews, showingCount: true)) <= width {
            return Line(heading: heading, showsCount: true)
        }
        let actions = trailing(subviews, showingCount: false)
        if lineWidth(heading: heading.width, trailing: actions) <= width {
            return Line(heading: heading, showsCount: false)
        }
        let room = max(width - lineWidth(heading: 0, trailing: actions), 0)
        return Line(heading: subviews[0].sizeThatFits(ProposedViewSize(width: room, height: nil)), showsCount: false)
    }

    /// A heading followed by what is at the far end, with the spacing on either side of the spacer between them.
    private func lineWidth(heading: CGFloat, trailing: CGFloat) -> CGFloat {
        heading + 2 * Self.spacing + (trailing > 0 ? Self.spacing + trailing : 0)
    }

    /// The count, when shown, and the buttons, with the spacing between them.
    private func trailing(_ subviews: Subviews, showingCount: Bool) -> CGFloat {
        let widths = [showingCount ? subviews[1].sizeThatFits(.unspecified).width : 0,
                      subviews[2].sizeThatFits(.unspecified).width].filter { $0 > 0 }
        return widths.reduce(0, +) + Self.spacing * CGFloat(max(widths.count - 1, 0))
    }
}
