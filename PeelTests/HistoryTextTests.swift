import Foundation
@testable import Peel
import Testing

struct HistoryTextTests {
    @Test func theQuestionBeforeAPutBackIntoAGuardedPlaceSaysHowManyItemsItIsAbout() {
        #expect(
            HistoryDetailView.guardedQuestion(items: 1, places: ["Documents"])
                == "Peel cannot check the record of one item in History, so another program may have written it. Put it back into Documents only if Peel moved it."
        )
        #expect(
            HistoryDetailView.guardedQuestion(items: 3, places: ["Desktop", "Documents"])
                == "Peel cannot check the records of 3 items in History, so another program may have written them. Put them back into Desktop and Documents only if Peel moved them."
        )
    }

    @Test func saysToConnectTheDiskForOneItemOrForSeveral() {
        #expect(HistoryDetailView.connectTheDisk(for: 1) == "Connect the disk to put it back from its Trash.")
        #expect(HistoryDetailView.connectTheDisk(for: 2) == "Connect the disk to put them back from its Trash.")
    }

    @Test func theNotesSayWhatFollows() {
        #expect(HistoryList.unreadableNote.key == "Peel removes nothing until it can read History or you start over, so that everything it moves can be put back. Starting over keeps the old file beside the new one, and what it lists comes back only from the Trash in Finder.")
        #expect(HistoryList.journalSetAside.key == "A removal may be missing from History")
        #expect(HistoryList.journalSetAsideNote.key == "Peel could not read its record of a removal under way. Peel kept that file aside. If a removal was cut short, what it moved is in the Trash but is not listed here: you can drag it back out in Finder.")
    }
}
