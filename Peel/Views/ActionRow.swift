import PeelCore
import SwiftUI

/// Buttons together at the right edge, the last, the page's main action, at the edge itself, as `ActionRowPlan` says.
struct ActionRow: Layout {
    /// The space above the buttons, which a row with none to show leaves out too.
    var top: CGFloat = 0

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
        return ActionRowPlan(sizes: fitted, width: width, top: top)
    }
}

/// The buttons of a page, under its last group and outside any box, as System Settings has them under a list of
/// accounts. An action that concerns one row stays at that row's right end.
struct PageActions<Buttons: View>: View {
    @ViewBuilder let buttons: Buttons

    var body: some View {
        // A grouped form keeps the box around a section's rows whatever their background, and none around a footer.
        Section {
        } footer: {
            ActionRow { buttons }
        }
    }
}
