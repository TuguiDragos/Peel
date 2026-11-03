public import CoreGraphics

/// Where a notice's mark, words, detail and buttons go. The buttons stand beside the words while the notice is shorter
/// so, the words keep their lines, every word fits and the words stand no taller than three buttons: a detail wraps
/// beside a long button instead of leaving a line of its own to it, while a title never breaks for one and a long
/// notice reads as text with its buttons under it. Without buttons the words stand beside the mark while each fits on
/// one line. Otherwise the words and the detail take the whole width, and the buttons stand under them. The mark is
/// centered on the row while every line stays whole, else at the words' first line.
public struct NoticePlan: Equatable, Sendable {
    public let isBeside: Bool
    public let mark: CGRect
    public let words: CGRect
    public let detail: CGRect
    public let actions: CGRect
    public let size: CGSize

    /// - Parameters:
    ///   - mark: A mark with no width takes no room, nor the gap after it.
    ///   - actions: The buttons on one line. With no width there are none.
    ///   - actionsUnder: The buttons under the words, laid out across the whole width.
    ///   - words: The words' size at a width, or on one line for nil: a title, or a block that keeps its lines.
    ///   - detail: The detail's size likewise, under the words.
    public init(
        width: CGFloat?, mark: CGSize, actions: CGSize, actionsUnder: CGSize, markGap: CGFloat, detailGap: CGFloat,
        actionsGap: CGFloat, actionsTop: CGFloat, words: (CGFloat?) -> CGSize, detail: ((CGFloat?) -> CGSize)?
    ) {
        let markRoom = mark.width > 0 ? mark.width + markGap : 0
        let hasActions = actions.width > 0
        let actionsRoom = hasActions ? actionsGap + actions.width : 0
        let oneLine = Parts(words: words(nil), detail: detail?(nil))
        guard let width, width.isFinite else {
            let room = max(oneLine.words.width, oneLine.detail?.width ?? 0)
            self.init(
                arranged: oneLine, beside: true, room: room, width: markRoom + room + actionsRoom, mark: mark,
                markRoom: markRoom, actions: hasActions ? actions : .zero, gaps: (detailGap, actionsTop),
                linesKept: true
            )
            return
        }
        let room = max(width - markRoom - actionsRoom, 0)
        let wholeRoom = max(width - markRoom, 0)
        let beside = Parts(words: words(room), detail: detail?(room))
        let under = Parts(words: words(wholeRoom), detail: detail?(wholeRoom))
        let isBeside = hasActions
            ? beside.fit(in: room) && beside.words.height <= under.words.height
                && beside.height(detailGap) <= 3 * actions.height
                && max(mark.height, beside.height(detailGap), actions.height)
                < max(mark.height, under.height(detailGap)) + actionsTop + actionsUnder.height
            : oneLine.fit(in: wholeRoom)
        let parts = isBeside ? beside : under
        self.init(
            arranged: parts, beside: isBeside, room: isBeside ? room : wholeRoom, width: width, mark: mark,
            markRoom: markRoom, actions: !hasActions ? .zero : isBeside ? actions : actionsUnder,
            gaps: (detailGap, actionsTop),
            linesKept: parts.words.height <= oneLine.words.height
                && (parts.detail?.height ?? 0) <= (oneLine.detail?.height ?? 0)
        )
    }

    private struct Parts {
        let words: CGSize
        let detail: CGSize?

        func fit(in room: CGFloat) -> Bool {
            words.width <= room && (detail?.width ?? 0) <= room
        }

        func height(_ detailGap: CGFloat) -> CGFloat {
            words.height + (detail.map { detailGap + $0.height } ?? 0)
        }
    }

    private init(
        arranged parts: Parts, beside: Bool, room: CGFloat, width: CGFloat, mark: CGSize, markRoom: CGFloat,
        actions: CGSize, gaps: (detail: CGFloat, actionsTop: CGFloat), linesKept: Bool
    ) {
        let block = parts.height(gaps.detail)
        let height = beside ? max(mark.height, block, actions.height) : max(mark.height, block)
        let blockY = beside ? (height - block) / 2 : 0
        isBeside = beside
        self.mark = CGRect(
            origin: CGPoint(x: 0, y: beside && linesKept ? (height - mark.height) / 2 : blockY), size: mark
        )
        words = CGRect(x: markRoom, y: blockY, width: room, height: parts.words.height)
        detail = parts.detail.map {
            CGRect(x: markRoom, y: blockY + parts.words.height + gaps.detail, width: room, height: $0.height)
        } ?? .zero
        if actions.width <= 0 {
            self.actions = .zero
            size = CGSize(width: width, height: height)
        } else if beside {
            self.actions = CGRect(
                origin: CGPoint(x: width - actions.width, y: (height - actions.height) / 2), size: actions
            )
            size = CGSize(width: width, height: height)
        } else {
            self.actions = CGRect(x: 0, y: height + gaps.actionsTop, width: width, height: actions.height)
            size = CGSize(width: width, height: height + gaps.actionsTop + actions.height)
        }
    }
}
