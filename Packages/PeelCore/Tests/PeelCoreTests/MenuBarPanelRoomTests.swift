import Foundation
@testable import PeelCore
import Testing

struct MenuBarPanelRoomTests {
    @Test func fitsTheDisplayWithTheLeastRoom() {
        #expect(MenuBarPanelRoom.height(within: [959, 629]) == 621)
        #expect(MenuBarPanelRoom.height(within: [923]) == 915)
    }

    @Test func setsNoBoundWithoutADisplay() {
        #expect(MenuBarPanelRoom.height(within: []) == nil)
    }
}
