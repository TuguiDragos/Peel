import PeelCore
import SwiftUI

/// A notice's mark, words, detail and buttons, each named with `noticePart(_:)`, placed as `NoticePlan` says.
struct NoticeLayout: Layout {
    enum Part: Sendable { case mark, words, detail, actions }

    var markGap: CGFloat = 0
    var detailGap: CGFloat = 1
    var actionsGap: CGFloat = 10
    var actionsTop: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        plan(subviews, width: proposal.width).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let plan = plan(subviews, width: bounds.width)
        for subview in subviews {
            let frame = switch subview[NoticePart.self] {
            case .mark: plan.mark
            case .words: plan.words
            case .detail: plan.detail
            case .actions: plan.actions
            }
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    private func plan(_ subviews: Subviews, width: CGFloat?) -> NoticePlan {
        func part(_ part: Part) -> LayoutSubview? { subviews.first { $0[NoticePart.self] == part } }
        func size(of subview: LayoutSubview) -> (CGFloat?) -> CGSize {
            { subview.sizeThatFits(ProposedViewSize(width: $0, height: nil)) }
        }
        let actions = part(.actions)
        let oneLine = actions?.sizeThatFits(.unspecified) ?? .zero
        return NoticePlan(
            width: width, mark: part(.mark)?.sizeThatFits(.unspecified) ?? .zero, actions: oneLine,
            actionsUnder: width.flatMap { width in actions.map { size(of: $0)(width) } } ?? oneLine,
            markGap: markGap, detailGap: detailGap, actionsGap: actionsGap, actionsTop: actionsTop,
            words: part(.words).map(size(of:)) ?? { _ in .zero }, detail: part(.detail).map(size(of:))
        )
    }
}

nonisolated private struct NoticePart: LayoutValueKey {
    static let defaultValue = NoticeLayout.Part.words
}

extension View {
    /// What this view is to its `NoticeLayout`.
    func noticePart(_ part: NoticeLayout.Part) -> some View {
        layoutValue(key: NoticePart.self, value: part)
    }
}
