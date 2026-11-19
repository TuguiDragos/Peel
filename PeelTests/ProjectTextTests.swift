import Foundation
@testable import Peel
import Testing

struct ProjectTextTests {
    @Test func theNotesAreShort() {
        #expect(ProjectDetailView.buildLeftNote.key == "What a build makes again, and what it installed. Nothing is selected for you; Select Recommended selects what Peel is sure about.")
        #expect(ProjectDetailView.backupsNote.key == "Backups skip the folders listed here, such as node_modules and Pods, and keep the project. Installed packages, folders with a generic name, and folders Peel does not select stay in backups. A folder a build makes again comes back without the mark.")
        #expect(ProjectList.cutShortTitle.key == "Some projects may be missing")
        #expect(ProjectList.cutShortNote("10,000").key == "Peel stopped after %@ folders in one of the folders you chose. Choose the folder your projects are in to see them.")
    }
}
