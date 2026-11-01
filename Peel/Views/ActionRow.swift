import PeelCore
import SwiftUI

/// The buttons at the foot of a page, laid out by `ActionRowPlan`: one is centered, and of two, what leads elsewhere
/// goes at the left end and the main action at the right. `keepsTogether` is for buttons that all act on one thing.
struct ActionRow: Layout {
    var keepsTogether = false

    func makeCache(subviews: Subviews) -> [CGSize] {
        subviews.map { $0.sizeThatFits(.unspecified) }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout [CGSize]) -> CGSize {
        plan(subviews, cache, width: proposal.width).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout [CGSize]) {
        for (subview, frame) in zip(subviews, plan(subviews, cache, width: bounds.width).frames) {
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    /// What is wider than the row, such as a sentence beside a button, is asked how tall it gets at the row's width.
    private func plan(_ subviews: Subviews, _ sizes: [CGSize], width: CGFloat?) -> ActionRowPlan {
        let fitted = zip(subviews, sizes).map { subview, size in
            guard let width, size.width > width else { return size }
            return subview.sizeThatFits(ProposedViewSize(width: width, height: nil))
        }
        return ActionRowPlan(sizes: fitted, width: width, keepsTogether: keepsTogether)
    }
}
