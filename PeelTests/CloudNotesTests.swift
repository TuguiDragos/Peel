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

    @Test func showsTheNoteColumnWhileARowHasANote() {
        var picture = Self.download("Beach.heic")
        picture.isDesktopPicture = true

        #expect(!CloudView.hasNoteColumn([Self.download("Notes.pdf")]))
        #expect(CloudView.hasNoteColumn([Self.download("Notes.pdf"), picture]))
        #expect(picture.note != nil)
        var kept = Self.download("Trip.pdf")
        kept.heldBack = .keptDownloaded
        #expect(CloudView.hasNoteColumn([kept]))
    }
}
