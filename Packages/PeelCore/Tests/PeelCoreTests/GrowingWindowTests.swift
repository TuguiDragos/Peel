import CoreGraphics
@testable import PeelCore
import Testing

struct GrowingWindowTests {
    private let macBook = CGRect(x: 0, y: 0, width: 1470, height: 923)

    @Test func aWindowThatGrewPastTheBottomMovesUpByWhatItPassed() {
        let grown = CGRect(x: 355, y: -36, width: 760, height: 608)
        #expect(GrowingWindow.frame(grown, within: macBook) == CGRect(x: 355, y: 0, width: 760, height: 608))
    }

    @Test func aWindowWithinTheScreenStaysWhereItIs() {
        let window = CGRect(x: 355, y: 352, width: 760, height: 220)
        #expect(GrowingWindow.frame(window, within: macBook) == window)
    }

    @Test func aWindowTallerThanTheScreenKeepsItsTopAtTheTopOfTheScreen() {
        let small = CGRect(x: 0, y: 0, width: 1024, height: 633)
        let grown = CGRect(x: 100, y: -200, width: 760, height: 700)
        #expect(GrowingWindow.frame(grown, within: small) == CGRect(x: 100, y: -67, width: 760, height: 700))
    }

    @Test func aWindowIsNeverMovedDown() {
        let high = CGRect(x: 355, y: 500, width: 760, height: 608)
        #expect(GrowingWindow.frame(high, within: macBook) == high)
    }

    @Test func aScreenBesideTheMainOneIsMeasuredFromItsOwnBottom() {
        let external = CGRect(x: 1470, y: -272, width: 1920, height: 1055)
        let grown = CGRect(x: 2000, y: -300, width: 760, height: 608)
        #expect(GrowingWindow.frame(grown, within: external) == CGRect(x: 2000, y: -272, width: 760, height: 608))
    }
}
