import Foundation
@testable import Peel
@testable import PeelCore
import Testing

struct CloudNotesTests {
    private static func download(_ name: String) -> CloudFile {
        CloudFile(
            url: URL(filePath: "/org.example/\(name)"), name: name, container: "iCloud Drive", size: 2_000_000,
            modified: nil
        )
    }

    /// The note column is on while a listed download has a note, so the note is drawn beside its row.
    @Test func showsTheNoteColumnWhileARowHasANote() {
        var picture = Self.download("Beach.heic")
        picture.isDesktopPicture = true

        #expect(!CloudView.hasNoteColumn([Self.download("Notes.pdf")]))
        #expect(CloudView.hasNoteColumn([Self.download("Notes.pdf"), picture]))
        #expect(picture.note != nil)
    }
}
