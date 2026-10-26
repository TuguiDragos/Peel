import SwiftUI

/// Lays its content out at its ideal height, or at `maximum` when that is less, so a list inside can scroll rather
/// than run past the screen.
struct UpToHeight: Layout {
    let maximum: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let content = subviews.first else { return .zero }
        let ideal = content.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
        guard ideal.height > maximum else { return ideal }
        return content.sizeThatFits(ProposedViewSize(width: proposal.width, height: maximum))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
    }
}
