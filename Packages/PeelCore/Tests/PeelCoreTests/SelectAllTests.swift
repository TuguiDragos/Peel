import Foundation
@testable import PeelCore
import Testing

struct SelectAllTests {
    private let repository = URL(filePath: "/tmp/org.example.Work")
    private let cache = URL(filePath: "/tmp/org.example.Cache")
    private let log = URL(filePath: "/tmp/org.example.Log")
    private let elsewhere = URL(filePath: "/tmp/org.example.Elsewhere")

    /// A row held back from Select All can still be selected by hand, and Deselect All takes it out with the rest:
    /// otherwise it would stay selected unseen and move with the next small file.
    @Test func deselectAllTakesOutARowSelectedByHand() {
        let rows = [repository, cache, log]
        let selectable = [cache, log]
        let selection: Set = [repository, cache, log, elsewhere]
        #expect(SelectAll.isAllSelected(selectable, in: selection))
        #expect(SelectAll.toggled(selection, selectable: selectable, rows: rows) == [elsewhere])
    }

    @Test func selectAllAddsOnlyWhatCanBeSelected() {
        let rows = [repository, cache, log]
        let selectable = [cache, log]
        let selection: Set = [cache]
        #expect(!SelectAll.isAllSelected(selectable, in: selection))
        #expect(SelectAll.toggled(selection, selectable: selectable, rows: rows) == [cache, log])
    }
}
