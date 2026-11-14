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

    @Test func aRowSaysItsDayWhileAnyRowOfThePageHasOne() throws {
        let day = Date(timeIntervalSince1970: 1_700_000_000)
        func item(_ date: Date?) -> InstallerItem {
            InstallerItem(
                url: URL(filePath: "/Users/me/Downloads/Tool.dmg.part"), kind: .incompleteDownload,
                name: "Tool.dmg.part", size: 4_096, date: date, installedApp: nil, isReadOnly: false, notes: []
            )
        }

        let dated = try #require(InstallerDetailView.day(of: item(day), showsDays: true))
        #expect(String(localized: dated) == day.formatted(.dateTime.day().month(.abbreviated).year()))
        let undated = try #require(InstallerDetailView.day(of: item(nil), showsDays: true))
        #expect(String(localized: undated) == String(localized: "Unknown"))
        #expect(InstallerDetailView.day(of: item(day), showsDays: false) == nil)
    }
}
