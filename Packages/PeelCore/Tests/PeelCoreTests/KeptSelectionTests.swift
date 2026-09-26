import Foundation
@testable import PeelCore
import Testing

struct KeptSelectionTests {
    private func url(_ name: String) -> URL {
        URL(filePath: "/Users/me/Library/Caches/\(name)")
    }

    /// A page starts from Peel's suggestion. Scanned again with the same items, it keeps what the person
    /// deselected deselected, and what they selected selected.
    @Test func keepsWhatThePersonChoseWhenThePageIsScannedAgain() {
        var kept = KeptSelection()
        let items: Set = [url("a"), url("b"), url("c")]
        var selected = kept.update([], selectable: items, suggested: [url("a"), url("b")])
        #expect(selected == [url("a"), url("b")])

        selected.remove(url("a"))
        selected.insert(url("c"))
        #expect(kept.update(selected, selectable: items, suggested: [url("a"), url("b")]) == [url("b"), url("c")])
    }

    /// What the person could already see keeps its checkbox, even when Peel would suggest it now. The suggestion
    /// goes to an item new to the page.
    @Test func suggestsOnlyWhatIsNewToThePage() {
        var kept = KeptSelection()
        let selected = kept.update([], selectable: [url("seen")], suggested: [])

        #expect(kept.update(selected, selectable: [url("seen"), url("new")], suggested: [url("seen"), url("new")]) == [url("new")])
    }

    /// An item that could not be selected, such as one that needs the helper while it is not there, was never the
    /// person's to choose. Once it can be selected, it takes Peel's suggestion.
    @Test func anItemThatCouldNotBeSelectedTakesTheSuggestionOnceItCan() {
        var kept = KeptSelection()
        let selected = kept.update([], selectable: [url("free")], suggested: [url("free"), url("locked")])
        #expect(selected == [url("free")])

        #expect(kept.update(selected, selectable: [url("free"), url("locked")], suggested: [url("free"), url("locked")]) == [url("free"), url("locked")])
    }

    @Test func dropsWhatIsGoneOrCanNoLongerBeSelected() {
        var kept = KeptSelection()
        let selected = kept.update([], selectable: [url("a"), url("b")], suggested: [url("a"), url("b")])

        #expect(kept.update(selected, selectable: [url("a")], suggested: [url("a")]) == [url("a")])
        #expect(kept.update([url("a")], selectable: [], suggested: []).isEmpty)
    }

    /// An item Peel selected for the person leaves the selection once Peel no longer suggests it, since what it
    /// was selected for has changed. An item the person picked on their own stays.
    @Test func dropsWhatPeelSelectedOnceItNoLongerSuggestsIt() {
        var kept = KeptSelection()
        var selected = kept.update([], selectable: [url("suggested"), url("picked")], suggested: [url("suggested")])
        selected.insert(url("picked"))

        #expect(kept.update(selected, selectable: [url("suggested"), url("picked")], suggested: []) == [url("picked")])
    }

    /// A forgotten item takes Peel's suggestion at the next update, as if it were new, and only that item.
    @Test func aForgottenItemTakesPeelsSuggestionAgain() {
        var kept = KeptSelection()
        _ = kept.update([], selectable: [url("a"), url("b")], suggested: [url("a"), url("b")])

        kept.forget([url("a")])
        #expect(kept.update([], selectable: [url("a"), url("b")], suggested: [url("a"), url("b")]) == [url("a")])
    }

    @Test func remembersTheSelectionItMade() {
        var kept = KeptSelection()
        let selected = kept.update([], selectable: [url("a"), url("b")], suggested: [url("a")])

        #expect(kept.made == selected)
    }
}
