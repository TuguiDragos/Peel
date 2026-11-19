import Foundation
@testable import Peel
import Testing

struct CloudTextTests {
    @Test func thePageAndItsSectionSayWhatRemoveDownloadsDoes() {
        #expect(CloudView.aboutCloud.key == "Files in iCloud that are also downloaded to this Mac. Remove Downloads takes away only the copy here; each file stays in iCloud and downloads again when you open it.")
        #expect(CloudView.onThisMacNote.key == "Finder still lists these files after their downloads are removed. Peel never deletes a file from iCloud.")
    }

    @Test func aListPeelDidNotReadWholeSaysWhyInItsCircledI() {
        #expect(CloudView.partlyReadTitle.key == "Peel did not read all of iCloud Drive")
        #expect(CloudView.whyPartlyRead(restNotRead: false, folders: []).isEmpty)
        #expect(CloudView.whyPartlyRead(restNotRead: true, folders: []).map(\.key) == ["macOS kept Peel out of the rest, so this list may not be complete."])
        #expect(CloudView.whyPartlyRead(restNotRead: false, folders: ["Documents"]).map(\.key) == ["macOS kept Peel out of %@, so this list may not be complete."])
        #expect(CloudView.whyPartlyRead(restNotRead: true, folders: ["Documents"]).count == 2)
        #expect(CloudView.tooBigTitle.key == "iCloud Drive is too big to read in one scan")
        #expect(CloudView.tooBigNote.key == "So this list is not all of it.")
    }
}
