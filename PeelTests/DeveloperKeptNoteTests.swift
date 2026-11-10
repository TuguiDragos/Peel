import Foundation
@testable import Peel
import Testing

struct DeveloperKeptNoteTests {
    /// The note is the same on every tool's page, so it says the rule and leaves each reason to its row.
    @Test func theKeptNoteSaysTheRuleFirstAndNamesNoOtherTool() {
        let note = DeveloperDetailView.keptNote.key

        #expect(note.hasPrefix("Peel doesn’t select these for you"), "\(note)")
        #expect(note.split(separator: " ").count < 30)
    }
}
