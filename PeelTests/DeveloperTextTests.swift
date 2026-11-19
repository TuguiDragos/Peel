import Foundation
@testable import Peel
import Testing

struct DeveloperTextTests {
    @Test func theNotesAreShort() {
        #expect(DeveloperDetailView.modelsNote("Ollama").key == "To remove one model, use the commands of %@ in Terminal. They delete for good, without the Trash, and Peel never runs them.")
        #expect(DeveloperDetailView.keptElsewhereNote("~/.ollama/models").key == "Peel leaves out %@. It does not follow a link to a folder kept elsewhere.")
    }
}
