@testable import Peel
import Testing

@MainActor
struct HistoryEmptyStateTests {
    private func state(
        hasLoaded: Bool = true, isKnownEmpty: Bool = false, filterIsOn: Bool = true, goneWhole: Int? = 0,
        listsNothing: Bool = true, isSearching: Bool = false
    ) -> HistoryList.EmptyState? {
        HistoryList.emptyState(
            hasLoaded: hasLoaded, isKnownEmpty: isKnownEmpty, filterIsOn: filterIsOn, goneWhole: goneWhole,
            listsNothing: listsNothing, isSearching: isSearching
        )
    }

    @Test func underTheFilterASearchThatFindsNothingSaysSoWhileRemovalsHaveLeftTheTrash() {
        #expect(state(goneWhole: 3, isSearching: true) == .nothingFound)
        #expect(state(goneWhole: 0, isSearching: true) == .nothingHasLeftTheTrash)
        #expect(state(goneWhole: 0) == .nothingHasLeftTheTrash)
        #expect(state(goneWhole: 3, listsNothing: false) == nil)
    }

    @Test func aHistoryForgetEmptiedSaysNoRemovalsUnderTheFilterToo() {
        #expect(state(isKnownEmpty: true, goneWhole: 0) == .noRemovals)
        #expect(state(isKnownEmpty: true, filterIsOn: false, goneWhole: nil) == .noRemovals)
    }

    @Test func looksBeforeItSaysAnything() {
        #expect(state(hasLoaded: false) == .looking)
        #expect(state(goneWhole: nil) == .looking)
        #expect(state(filterIsOn: false, goneWhole: nil, isSearching: true) == .nothingFound)
    }
}
