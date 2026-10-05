import Foundation
@testable import PeelCore
import Testing

struct SelectableRowsTests {
    private let repository = URL(filePath: "/tmp/org.example.Work")
    private let cache = URL(filePath: "/tmp/org.example.Cache")
    private let log = URL(filePath: "/tmp/org.example.Log")
    private let elsewhere = URL(filePath: "/tmp/org.example.Elsewhere")

    /// A row selected by hand that Select All leaves alone goes with Deselect All too: otherwise it would stay
    /// selected unseen and move with the next small file.
    @Test func deselectAllTakesOutARowSelectedByHand() {
        let list = SelectableRows(rows: [repository, cache, log], selectable: [cache, log], recommended: [cache, log])
        let selection: Set = [repository, cache, log, elsewhere]

        #expect(list.isAllSelected(in: selection))
        #expect(list.deselectingAll(in: selection) == [elsewhere])
    }

    @Test func selectAllAddsWhatAClickCanSelect() {
        let list = SelectableRows(rows: [repository, cache, log], selectable: [cache, log], recommended: [cache])

        #expect(list.selectingAll(in: [elsewhere]) == [cache, log, elsewhere])
        #expect(list.isAllSelected(in: [cache, log]))
    }

    @Test func selectRecommendedTakesOutWhatPeelDoesNotRecommend() {
        let list = SelectableRows(
            rows: [repository, cache, log], selectable: [repository, cache, log], recommended: [cache]
        )
        let selection: Set = [repository, log, elsewhere]

        #expect(!list.isRecommendedSelected(in: selection))
        #expect(list.selectingRecommended(in: selection) == [cache, elsewhere])
        #expect(list.isRecommendedSelected(in: [cache, elsewhere]))
        #expect(!list.isRecommendedSelected(in: [cache, log]))
    }

    @Test func selectAllAsksOnlyAboutWhatPeelDoesNotRecommend() {
        let list = SelectableRows(
            rows: [repository, cache, log], selectable: [repository, cache, log], recommended: [cache]
        )

        #expect(list.notRecommendedAdded(by: []) == [repository, log])
        #expect(list.notRecommendedAdded(by: [repository]) == [log])
        #expect(list.notRecommendedAdded(by: [repository, log]).isEmpty)
        let everything = SelectableRows(rows: [cache, log], selectable: [cache, log], recommended: [cache, log])
        #expect(everything.notRecommendedAdded(by: []).isEmpty)
    }

    @Test func peelNeverRecommendsWhatAClickCannotSelect() {
        let list = SelectableRows(rows: [repository, cache], selectable: [cache], recommended: [repository, cache])

        #expect(list.recommended == [cache])
        #expect(list.selectingRecommended(in: []) == [cache])
    }

    @Test func deselectAllLeavesOtherListsAlone() {
        let list = SelectableRows(rows: [cache, log], selectable: [cache, log], recommended: [cache])

        #expect(list.isNoneSelected(in: [elsewhere]))
        #expect(!list.isNoneSelected(in: [log, elsewhere]))
        #expect(list.deselectingAll(in: [log, elsewhere]) == [elsewhere])
        let locked = SelectableRows(rows: [repository, cache], selectable: [cache], recommended: [cache])
        #expect(!locked.isNoneSelected(in: [repository]))
    }
}
