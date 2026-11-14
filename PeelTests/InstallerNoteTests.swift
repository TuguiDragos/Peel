import Foundation
@testable import Peel
@testable import PeelCore
import Testing

@MainActor
struct InstallerNoteTests {
    @Test func aCopySharingItsStorageSaysWhyItFreesLessThanItsSize() throws {
        var item = InstallerItem(
            url: URL(filePath: "/Users/me/Documents/Tool copy.xip"), kind: .appInstaller, name: "Tool copy.xip",
            size: 4_096, date: nil, installedApp: nil, isReadOnly: false, notes: []
        )
        #expect(InstallerDetailView.warning(for: item) == nil)

        item.takesOnDisk = 600_000_000
        let note = try #require(InstallerDetailView.warning(for: item))
        #expect(note.contains(Int64(600_000_000).byteCount))

        item.heldBack = .arrivedRecently
        #expect(InstallerDetailView.warning(for: item)?.components(separatedBy: "\n\n").count == 2)
    }
}
