import Foundation
@testable import Peel
import Testing

struct OrphansTextTests {
    @Test func theStatesAreShortWithTheRestInTheirNote() {
        #expect(OrphanList.ownersUnreadable.key == "Peel cannot read which app owns these files")
        #expect(OrphanList.ownersUnreadableNote.key == "So they are listed here again. Start the list over in Settings > Exclusions.")
        #expect(OrphanList.appsNotKnown.key == "Peel cannot tell which apps are installed")
        #expect(OrphanList.placesUnread(3).key == "It did not read ^[%lld place](inflect: true) where apps are. Nothing is listed, since the files of an app it cannot see would look orphaned.")
        #expect(OrphanDetailView.temporaryCopyNote.key == "It was a temporary copy, such as one an installer opens.")
        #expect(AdministratorItemsView.howToRemove.key == "Only an administrator can move these, and the Peel helper cannot. To remove one, show it in Finder, drag it to the Trash, and enter an administrator name and password.")
    }
}
