import Foundation
@testable import Peel
import Testing

struct HistoryTextTests {
    @Test func theNotesSayWhatFollows() {
        #expect(HistoryList.unreadableNote.key == "Peel removes nothing until it can read History or you start over, so that everything it moves can be put back. Starting over keeps the old file beside the new one, and what it lists comes back only from the Trash in Finder.")
        #expect(HistoryList.journalSetAside.key == "A removal may be missing from History")
    }
}
