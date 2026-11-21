@testable import Peel
import Testing

@MainActor
struct HistoryEmptyStateTests {
    private func state(
        hasLoaded: Bool = true, isKnownEmpty: Bool = false, listsNothing: Bool = true, isSearching: Bool = false
    ) -> HistoryList.EmptyState? {
        HistoryList.emptyState(
            hasLoaded: hasLoaded, isKnownEmpty: isKnownEmpty, listsNothing: listsNothing, isSearching: isSearching
        )
    }

    @Test func aSearchThatFindsNothingSaysSo() {
        #expect(state(isSearching: true) == .nothingFound)
        #expect(state(listsNothing: false, isSearching: true) == nil)
        #expect(state(listsNothing: false) == nil)
    }

    @Test func aHistoryForgetEmptiedSaysNoRemovals() {
        #expect(state(isKnownEmpty: true) == .noRemovals)
        #expect(state(isKnownEmpty: true, isSearching: true) == .noRemovals)
    }

    @Test func readsHistoryBeforeItSaysAnything() {
        #expect(state(hasLoaded: false) == .loading)
        #expect(state(hasLoaded: false, isKnownEmpty: true, isSearching: true) == .loading)
    }

    @Test func theSpinnerOfTheFirstReadFollowsTheBusyTiming() {
        #expect(HistoryList.drawn(.loading, loadShows: false) == nil)
        #expect(HistoryList.drawn(.loading, loadShows: true) == .loading)
        #expect(HistoryList.drawn(nil, loadShows: true) == .loading)
        #expect(HistoryList.drawn(.nothingFound, loadShows: true) == .loading)
        #expect(HistoryList.drawn(.noRemovals, loadShows: false) == .noRemovals)
        #expect(HistoryList.drawn(nil, loadShows: false) == nil)
    }
}
