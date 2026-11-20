import Foundation
@testable import Peel
import Testing

@MainActor
struct ResetSheetNoteTests {
    /// The copy outlives the sheet, so the sheet says where it stays and that it stays until moved to the Trash.
    @Test func theSheetSaysWhereTheSavedCopyStays() {
        let note = String(localized: ResetSheet.changeOfMindNote)

        #expect(note.contains("Settings > General > Saved Settings"))
        #expect(note.contains("until you move it to the Trash"))
    }

    @Test func whatTheResetMovesIsOneItOrSeveralThem() {
        func sentence(_ count: Int, copies: Bool) -> String {
            let sentence = ResetSheet.movesSentence(count: count, size: "4 KB", app: "Tide", copiesSettings: copies)
            return String(AttributedString(localized: sentence).characters)
        }

        #expect(sentence(1, copies: false) == "Peel moves 1 item, 4 KB, to the Trash. Tide opens without it.")
        #expect(sentence(3, copies: false) == "Peel moves 3 items, 4 KB, to the Trash. Tide opens without them.")
        #expect(sentence(1, copies: true).hasSuffix("copies the settings first. Tide opens without it."))
        #expect(sentence(2, copies: true).hasSuffix("copies the settings first. Tide opens without them."))
    }
}
