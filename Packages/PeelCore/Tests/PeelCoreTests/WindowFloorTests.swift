import CoreGraphics
@testable import PeelCore
import Testing

/// How small the main window may be: the whole floor where the screen has room for it, and the screen's own size
/// where it does not, so the window never runs off a small screen.
struct WindowFloorTests {
    @Test func aScreenWithRoomKeepsTheWholeFloor() {
        #expect(WindowFloor.size(within: CGSize(width: 1470, height: 923)) == CGSize(width: 1307, height: 756))
        #expect(WindowFloor.size(within: CGSize(width: 1920, height: 1080)) == CGSize(width: 1307, height: 756))
    }

    @Test func aScreenNarrowerThanTheFloorGetsItsOwnWidth() {
        #expect(WindowFloor.size(within: CGSize(width: 1280, height: 799)) == CGSize(width: 1280, height: 756))
    }

    @Test func aScreenSmallerThanTheFloorEitherWayGetsItsOwnSize() {
        #expect(WindowFloor.size(within: CGSize(width: 1024, height: 633)) == CGSize(width: 1024, height: 633))
    }
}
