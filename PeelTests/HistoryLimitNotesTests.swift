import Foundation
@testable import Peel
import PeelCore
import Testing

struct HistoryLimitNotesTests {
    /// "No longer lists" read as a loss: each note says the limit that left the older removals out.
    @Test func eachNoteSaysTheLimitThatLeftOlderRemovalsOut() {
        let history = HistoryList.historyKeepsItsLatest
        let notMoved = HistoryList.notMovedKeepsItsLatest

        #expect(history.contains(RemovalLog.maximumRecords.formatted()), "\(history)")
        #expect(notMoved.contains(RefusalLog.maximumRecords.formatted()), "\(notMoved)")
    }
}
