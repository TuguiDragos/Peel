@testable import Peel
import Testing

@MainActor
struct HistoryEmptyStateTests {
    private func state(
        hasLoaded: Bool = true, isKnownEmpty: Bool = false, filterIsOn: Bool = true, leftTheTrash: Int? = 0,
        listsNothing: Bool = true, isSearching: Bool = false
    ) -> HistoryList.EmptyState? {
        HistoryList.emptyState(
            hasLoaded: hasLoaded, isKnownEmpty: isKnownEmpty, filterIsOn: filterIsOn, leftTheTrash: leftTheTrash,
            listsNothing: listsNothing, isSearching: isSearching
        )
    }

    @Test func underTheFilterASearchThatFindsNothingSaysSoWhileRemovalsHaveLeftTheTrash() {
        #expect(state(leftTheTrash: 3, isSearching: true) == .nothingFound)
        #expect(state(leftTheTrash: 0, isSearching: true) == .nothingHasLeftTheTrash)
        #expect(state(leftTheTrash: 0) == .nothingHasLeftTheTrash)
        #expect(state(leftTheTrash: 3, listsNothing: false) == nil)
    }

    @Test func aHistoryForgetEmptiedSaysNoRemovalsUnderTheFilterToo() {
        #expect(state(isKnownEmpty: true, leftTheTrash: 0) == .noRemovals)
        #expect(state(isKnownEmpty: true, filterIsOn: false, leftTheTrash: nil) == .noRemovals)
    }

    @Test func looksBeforeItSaysAnything() {
        #expect(state(hasLoaded: false) == .looking)
        #expect(state(leftTheTrash: nil) == .looking)
        #expect(state(filterIsOn: false, leftTheTrash: nil, isSearching: true) == .nothingFound)
    }

    @Test func saysWhatPeelCouldNotFindOutWhereNothingHasLeftTheTrash() {
        let everything = "Everything these removals moved is still in the Trash, so Put Back can bring it back."
        #expect(HistoryList.nothingLeftDetail(away: 0, notKnown: 0) == everything)
        #expect(
            HistoryList.nothingLeftDetail(away: 3, notKnown: 0)
                == "3 items on a disk that isn’t connected\nConnect the disk to put them back from its Trash."
        )
        #expect(
            HistoryList.nothingLeftDetail(away: 0, notKnown: 2)
                == "Peel can’t look in the Trash right now\nHistory keeps what it can’t see until Peel can look again."
        )
        #expect(!HistoryList.nothingLeftDetail(away: 1, notKnown: 1).contains(everything))
    }
}
