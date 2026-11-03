import Foundation
@testable import Peel
import PeelCore
import Testing

struct MovesHeldTests {
    private static let full = HistoryWriteProblem.diskFull(free: 1_000, needed: 1_000_002)

    @Test func namesWhatKeepsEveryMoveBack() {
        func reason(_ exclusions: Bool, _ history: Bool, _ writing: Bool) -> MovesHeld? {
            MovesHeld.reason(
                exclusionsUnreadable: exclusions, historyUnreadable: history,
                historyUnwritable: writing ? Self.full : nil
            )
        }

        #expect(reason(false, false, false) == nil)
        #expect(reason(true, true, true) == .exclusionsUnreadable)
        #expect(reason(false, true, true) == .historyUnreadable)
        #expect(reason(false, false, true) == .historyUnwritable(Self.full))
    }

    @Test func anActionHistoryDoesntRecordWaitsOnlyForTheExclusions() {
        func reason(_ exclusions: Bool, _ history: Bool, _ writing: Bool) -> MovesHeld? {
            MovesHeld.reason(
                exclusionsUnreadable: exclusions, historyUnreadable: history,
                historyUnwritable: writing ? Self.full : nil, recordsInHistory: false
            )
        }

        #expect(reason(false, true, false) == nil)
        #expect(reason(false, false, true) == nil)
        #expect(reason(true, true, true) == .exclusionsUnreadable)
    }
}
