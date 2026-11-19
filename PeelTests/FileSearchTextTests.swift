import Foundation
@testable import Peel
import PeelCore
import Testing

struct FileSearchTextTests {
    @Test func theFiltersNoteIsShort() {
        #expect(FileSearchForm.filtersNote.key == "Peel searches the Spotlight index of the disks of this Mac, not network volumes. Folders, apps, and system files are left out. What apps keep in a Library folder is listed last, and Select Recommended leaves it out.")
    }

    @Test func eachLineOfWhatWasLeftOutIsShortWithWhyInItsCircledI() {
        #expect(LeftOutLines.title(for: .syncs, count: 3).key == "Left out: ^[%lld file](inflect: true) in a place that syncs to your other devices")
        #expect(LeftOutLines.note(for: .syncs)?.key == "Peel never moves what syncs, since moving it to the Trash would also remove it from your other devices.")
        #expect(LeftOutLines.title(for: .protected, count: 3).key == "Left out: ^[%lld file](inflect: true) in places Peel never moves from")
        #expect(LeftOutLines.note(for: .protected)?.key == "Such as macOS itself, Mail, Messages, or a photo library.")
        #expect(LeftOutLines.title(for: .exclusionsNotKnown, count: 3).key == "Left out: ^[%lld file](inflect: true) until Peel can read your exclusions.")
        #expect(LeftOutLines.note(for: .exclusionsNotKnown) == nil)
        #expect(LeftOutLines.note(for: .excluded) == nil)
    }
}
