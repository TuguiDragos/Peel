import SwiftUI

/// Lays out one view as it is, but never lets it decide where a list row's separator starts. A `Label` marks its
/// title as that start, so a status or a tag beside a row's title would pull the separator under itself.
struct LeavesRowSeparatorAlone: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        subviews.first?.sizeThatFits(proposal) ?? .zero
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
    }

    func explicitAlignment(
        of guide: HorizontalAlignment,
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGFloat? {
        guard guide != .listRowSeparatorLeading, let view = subviews.first else { return nil }
        return view.dimensions(in: ProposedViewSize(bounds.size))[explicit: guide].map { bounds.minX + $0 }
    }
}
