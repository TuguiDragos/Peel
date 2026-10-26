@testable import Peel
import Testing

struct MovesHeldTests {
    @Test func namesWhatKeepsEveryMoveBack() {
        func reason(_ exclusions: Bool, _ history: Bool, _ writing: Bool) -> MovesHeld? {
            MovesHeld.reason(exclusionsUnreadable: exclusions, historyUnreadable: history, historyUnwritable: writing)
        }

        #expect(reason(false, false, false) == nil)
        #expect(reason(true, true, true) == .exclusionsUnreadable)
        #expect(reason(false, true, true) == .historyUnreadable)
        #expect(reason(false, false, true) == .historyUnwritable)
    }

    @Test func anActionHistoryDoesntRecordWaitsOnlyForTheExclusions() {
        func reason(_ exclusions: Bool, _ history: Bool, _ writing: Bool) -> MovesHeld? {
            MovesHeld.reason(
                exclusionsUnreadable: exclusions, historyUnreadable: history, historyUnwritable: writing,
                recordsInHistory: false
            )
        }

        #expect(reason(false, true, false) == nil)
        #expect(reason(false, false, true) == nil)
        #expect(reason(true, true, true) == .exclusionsUnreadable)
    }
}
