import CoreGraphics
@testable import PeelCore
import Testing

struct ActionRowPlanTests {
    private let small = CGSize(width: 100, height: 28)
    private let wide = CGSize(width: 300, height: 28)

    @Test func oneActionStandsAtTheRightEdge() {
        let plan = ActionRowPlan(sizes: [small], width: 400)
        #expect(plan.frames == [CGRect(x: 300, y: 0, width: 100, height: 28)])
        #expect(plan.size == CGSize(width: 400, height: 28))
    }

    @Test func actionsStandTogetherAtTheRightEdgeWithTheLastAtIt() {
        let plan = ActionRowPlan(sizes: [small, small, small], width: 400, spacing: 8)
        #expect(plan.frames.map(\.minX) == [84, 192, 300])
        #expect(plan.size.height == 28)
    }

    @Test func actionsThatJustFitStayOnOneLine() {
        let plan = ActionRowPlan(sizes: [wide, small], width: 408, spacing: 8)
        #expect(plan.frames.map(\.minX) == [0, 308])
        #expect(plan.size.height == 28)
    }

    @Test func actionsWithoutRoomTakeAnotherLineAboveTheLastOnes() {
        let plan = ActionRowPlan(sizes: [wide, small, small], width: 400, spacing: 8, lineSpacing: 6)
        #expect(plan.frames[0] == CGRect(x: 100, y: 0, width: 300, height: 28))
        #expect(plan.frames[1] == CGRect(x: 192, y: 34, width: 100, height: 28))
        #expect(plan.frames[2] == CGRect(x: 300, y: 34, width: 100, height: 28))
        #expect(plan.size == CGSize(width: 400, height: 62))
    }

    @Test func whatHasNoWidthTakesNoRoom() {
        let plan = ActionRowPlan(sizes: [.zero, small], width: 400)
        #expect(plan.frames[1] == CGRect(x: 300, y: 0, width: 100, height: 28))
        #expect(plan.frames[0].size == .zero)
        #expect(plan.size.height == 28)
    }

    @Test func aRowWithNothingInItHasNoHeight() {
        #expect(ActionRowPlan(sizes: [.zero], width: 400).size.height == 0)
        #expect(ActionRowPlan(sizes: [], width: 400).size.height == 0)
    }

    @Test func theSpaceAboveTheActionsIsThereOnlyWhileOneShows() {
        let plan = ActionRowPlan(sizes: [small], width: 400, top: 8)
        #expect(plan.frames == [CGRect(x: 300, y: 8, width: 100, height: 28)])
        #expect(plan.size.height == 36)
        #expect(ActionRowPlan(sizes: [.zero], width: 400, top: 8).size.height == 0)
    }

    @Test func leadingActionsStandAtTheLeftEdgeOnTheLineOfTheOthers() {
        let plan = ActionRowPlan(sizes: [small, small, small], width: 400, spacing: 8, leading: [true, true, false])
        #expect(plan.frames.map(\.minX) == [0, 108, 300])
        #expect(plan.frames.map(\.minY) == [0, 0, 0])
        #expect(plan.size == CGSize(width: 400, height: 28))
    }

    @Test func leadingActionsWithoutRoomBesideTheOthersTakeTheLineAbove() {
        let plan = ActionRowPlan(sizes: [wide, small], width: 380, spacing: 8, lineSpacing: 6, leading: [true, false])
        #expect(plan.frames[0] == CGRect(x: 0, y: 0, width: 300, height: 28))
        #expect(plan.frames[1] == CGRect(x: 280, y: 34, width: 100, height: 28))
        #expect(plan.size == CGSize(width: 380, height: 62))
    }

    @Test func aLeadingActionThatIsNotShownTakesNoRoom() {
        let plan = ActionRowPlan(sizes: [.zero, small], width: 400, leading: [true, false])
        #expect(plan.frames[1] == CGRect(x: 300, y: 0, width: 100, height: 28))
        #expect(plan.size.height == 28)
    }

    @Test func anActionWiderThanTheRowIsGivenTheWholeRow() {
        let plan = ActionRowPlan(sizes: [CGSize(width: 500, height: 28)], width: 400)
        #expect(plan.frames == [CGRect(x: 0, y: 0, width: 400, height: 28)])
    }

    @Test func aTallerActionCentersTheOthersOnItsLine() {
        let plan = ActionRowPlan(sizes: [CGSize(width: 100, height: 40), small], width: 400)
        #expect(plan.frames[1].minY == 6)
        #expect(plan.size.height == 40)
    }

    @Test func withoutAWidthTheRowIsAsWideAsItsActions() {
        let plan = ActionRowPlan(sizes: [small, small], width: nil, spacing: 8)
        #expect(plan.size == CGSize(width: 208, height: 28))
        #expect(ActionRowPlan(sizes: [small, small], width: .infinity, spacing: 8).size.width == 208)
    }
}
