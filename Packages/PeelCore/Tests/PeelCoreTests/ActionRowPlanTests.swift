import CoreGraphics
@testable import PeelCore
import Testing

struct ActionRowPlanTests {
    private let small = CGSize(width: 100, height: 28)
    private let wide = CGSize(width: 300, height: 28)

    @Test func oneActionIsCentered() {
        let plan = ActionRowPlan(sizes: [small], width: 400)
        #expect(plan.frames == [CGRect(x: 150, y: 0, width: 100, height: 28)])
        #expect(plan.size == CGSize(width: 400, height: 28))
    }

    @Test func twoActionsStandAtTheEndsOfTheRow() {
        let plan = ActionRowPlan(sizes: [small, small], width: 400)
        #expect(plan.frames[0] == CGRect(x: 0, y: 0, width: 100, height: 28))
        #expect(plan.frames[1] == CGRect(x: 300, y: 0, width: 100, height: 28))
        #expect(plan.size.height == 28)
    }

    @Test func twoActionsWithoutRoomTakeACenteredLineEach() {
        let plan = ActionRowPlan(sizes: [wide, small], width: 400, spacing: 8)
        #expect(plan.frames[0] == CGRect(x: 50, y: 0, width: 300, height: 28))
        #expect(plan.frames[1] == CGRect(x: 150, y: 36, width: 100, height: 28))
        #expect(plan.size == CGSize(width: 400, height: 64))
    }

    @Test func twoActionsThatJustFitStayOnOneLine() {
        let plan = ActionRowPlan(sizes: [wide, small], width: 408, spacing: 8)
        #expect(plan.frames[0].minX == 0)
        #expect(plan.frames[1].maxX == 408)
        #expect(plan.size.height == 28)
    }

    @Test func actionsKeptTogetherStayInTheMiddleHoweverManyTheyAre() {
        let two = ActionRowPlan(sizes: [small, small], width: 400, keepsTogether: true, spacing: 8)
        #expect(two.frames.map(\.minX) == [96, 204])
        let three = ActionRowPlan(sizes: [small, small, small], width: 400, keepsTogether: true, spacing: 8)
        #expect(three.frames.map(\.minX) == [42, 150, 258])
    }

    @Test func actionsKeptTogetherWithoutRoomTakeACenteredLineEach() {
        let plan = ActionRowPlan(sizes: [wide, wide], width: 400, keepsTogether: true, spacing: 8)
        #expect(plan.frames.map(\.minX) == [50, 50])
        #expect(plan.frames.map(\.minY) == [0, 36])
    }

    @Test func whatHasNoWidthTakesNoRoom() {
        let plan = ActionRowPlan(sizes: [.zero, small], width: 400)
        #expect(plan.frames[1] == CGRect(x: 150, y: 0, width: 100, height: 28))
        #expect(plan.frames[0].size == .zero)
        #expect(plan.size.height == 28)
    }

    @Test func aRowWithNothingInItHasNoHeight() {
        #expect(ActionRowPlan(sizes: [.zero], width: 400).size.height == 0)
        #expect(ActionRowPlan(sizes: [], width: 400).size.height == 0)
    }

    @Test func anActionWiderThanTheRowIsGivenTheWholeRow() {
        let plan = ActionRowPlan(sizes: [CGSize(width: 500, height: 28)], width: 400)
        #expect(plan.frames == [CGRect(x: 0, y: 0, width: 400, height: 28)])
    }

    @Test func aRowOfTallerActionsCentersTheShorterOnTheLine() {
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
