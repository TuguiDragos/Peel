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
}
