import CoreGraphics
@testable import PeelCore
import Testing

struct NoticePlanTests {
    private let mark = CGSize(width: 26, height: 26)

    /// Words that wrap as a paragraph does: `length` points of text, in lines of 15 points.
    private func text(_ length: CGFloat) -> (CGFloat?) -> CGSize {
        { width in
            guard let width, width < length else { return CGSize(width: length, height: 15) }
            return CGSize(width: width, height: (length / width).rounded(.up) * 15)
        }
    }

    private func plan(
        width: CGFloat?, mark: CGSize? = nil, actions: CGSize, markGap: CGFloat = 10,
        title: @escaping (CGFloat?) -> CGSize, detail: ((CGFloat?) -> CGSize)? = nil
    ) -> NoticePlan {
        let under = actions.width > 0 ? CGSize(width: width ?? actions.width, height: actions.height) : .zero
        return NoticePlan(
            width: width, mark: mark ?? self.mark, actions: actions, actionsUnder: under, markGap: markGap,
            detailGap: 1, actionsGap: 10, actionsTop: 8, words: title, detail: detail
        )
    }

    @Test func aDetailThatWrapsBesideALongButtonStaysBesideItWhileThatIsShorter() {
        let plan = plan(width: 520, actions: CGSize(width: 190, height: 28), title: text(250), detail: text(400))
        #expect(plan.isBeside)
        #expect(plan.words == CGRect(x: 36, y: 0, width: 284, height: 15))
        #expect(plan.detail == CGRect(x: 36, y: 16, width: 284, height: 30))
        #expect(plan.mark == CGRect(x: 0, y: 0, width: 26, height: 26))
        #expect(plan.actions == CGRect(x: 330, y: 9, width: 190, height: 28))
        #expect(plan.size == CGSize(width: 520, height: 46))
    }

    @Test func whileEveryLineStaysWholeTheMarkTheWordsAndTheButtonsShareOneAxis() {
        let plan = plan(width: 520, actions: CGSize(width: 150, height: 28), title: text(200), detail: text(200))
        #expect(plan.isBeside)
        #expect(plan.size.height == 31)
        #expect(plan.mark.minY == 2.5)
        #expect(plan.words.minY == 0)
        #expect(plan.actions.minY == 1.5)
    }

    @Test func aTitleThatWouldWrapBesideTheButtonsSendsThemUnder() {
        let plan = plan(
            width: 480, mark: CGSize(width: 24, height: 17), actions: CGSize(width: 100, height: 24), markGap: 8,
            title: text(400), detail: text(300)
        )
        #expect(!plan.isBeside)
        #expect(plan.words == CGRect(x: 32, y: 0, width: 448, height: 15))
        #expect(plan.detail == CGRect(x: 32, y: 16, width: 448, height: 15))
        #expect(plan.actions == CGRect(x: 0, y: 39, width: 480, height: 24))
        #expect(plan.size == CGSize(width: 480, height: 63))
    }

    @Test func theButtonsStandBesideOnlyWhereTheNoticeComesOutShorter() {
        let saving = plan(width: 520, actions: CGSize(width: 190, height: 28), title: text(250), detail: text(900))
        #expect(saving.isBeside)
        #expect(saving.detail.height == 60)
        let even = plan(width: 520, actions: CGSize(width: 190, height: 22), title: text(250), detail: text(900))
        #expect(!even.isBeside)
    }

    @Test func wordsTallerThanThreeButtonsKeepTheButtonsUnderThem() {
        let plan = plan(width: 900, actions: CGSize(width: 300, height: 22), title: text(200), detail: text(3500))
        #expect(!plan.isBeside)
        #expect(plan.detail.width == 864)
    }

    @Test func aNarrowColumnKeepsTheWholeWidthForTheDetail() {
        let plan = plan(
            width: 330, actions: CGSize(width: 100, height: 22), markGap: 8, title: text(120), detail: text(1200)
        )
        #expect(!plan.isBeside)
        #expect(plan.mark == CGRect(x: 0, y: 0, width: 26, height: 26))
        #expect(plan.detail == CGRect(x: 34, y: 16, width: 296, height: 75))
        #expect(plan.actions == CGRect(x: 0, y: 99, width: 330, height: 22))
    }

    @Test func withoutButtonsTheWordsStandBesideTheMarkOnlyOnOneLine() {
        let short = plan(width: 400, actions: .zero, title: text(300))
        #expect(short.isBeside)
        #expect(short.words == CGRect(x: 36, y: 5.5, width: 364, height: 15))
        #expect(short.size == CGSize(width: 400, height: 26))

        let long = plan(width: 400, actions: .zero, title: text(200), detail: text(500))
        #expect(!long.isBeside)
        #expect(long.mark == CGRect(x: 0, y: 0, width: 26, height: 26))
        #expect(long.detail == CGRect(x: 36, y: 16, width: 364, height: 30))
        #expect(long.size == CGSize(width: 400, height: 46))
    }

    @Test func aWordWiderThanTheRoomBesideTheButtonsSendsThemUnder() {
        let unbreakable: (CGFloat?) -> CGSize = { _ in CGSize(width: 300, height: 15) }
        let plan = plan(width: 400, actions: CGSize(width: 150, height: 28), title: text(100), detail: unbreakable)
        #expect(!plan.isBeside)
    }

    @Test func withoutAWidthEverythingStandsOnOneLine() {
        let plan = plan(width: nil, actions: CGSize(width: 190, height: 28), title: text(250), detail: text(400))
        #expect(plan.isBeside)
        #expect(plan.size == CGSize(width: 636, height: 31))
        #expect(plan.actions.minX == 446)
    }

    @Test func aMarkWithNoWidthTakesNoRoom() {
        let plan = plan(width: 520, mark: .zero, actions: CGSize(width: 190, height: 28), title: text(250))
        #expect(plan.isBeside)
        #expect(plan.words.minX == 0)
        #expect(plan.words.width == 320)
        #expect(plan.detail == .zero)
    }
}
