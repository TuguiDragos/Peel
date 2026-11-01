import Testing
@testable import PeelCore

struct ListHighlightTests {
    @Test func downFromNothingIsTheFirstRowAndUpIsTheLast() {
        #expect(ListHighlight.moved(from: nil, by: 1, among: ["a", "b", "c"]) == "a")
        #expect(ListHighlight.moved(from: nil, by: -1, among: ["a", "b", "c"]) == "c")
    }

    @Test func aStepMovesOneRow() {
        #expect(ListHighlight.moved(from: "a", by: 1, among: ["a", "b", "c"]) == "b")
        #expect(ListHighlight.moved(from: "c", by: -1, among: ["a", "b", "c"]) == "b")
    }

    @Test func theEndsOfTheListHold() {
        #expect(ListHighlight.moved(from: "c", by: 1, among: ["a", "b", "c"]) == "c")
        #expect(ListHighlight.moved(from: "a", by: -1, among: ["a", "b", "c"]) == "a")
    }

    @Test func aRowASearchTookAwayStartsOver() {
        #expect(ListHighlight.moved(from: "z", by: 1, among: ["a", "b"]) == "a")
        #expect(ListHighlight.moved(from: "z", by: -1, among: ["a", "b"]) == "b")
    }

    @Test func noRowsLeaveNothingHighlighted() {
        #expect(ListHighlight.moved(from: "a", by: 1, among: [String]()) == nil)
    }
}
