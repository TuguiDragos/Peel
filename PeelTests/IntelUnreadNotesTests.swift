import Foundation
@testable import Peel
import Testing

struct IntelUnreadNotesTests {
    /// An Intel Mac runs Intel code natively, so nothing it couldn't read is said to need Rosetta there.
    @Test func onAnIntelMacNothingIsSaidToNeedRosetta() {
        for onAppleSilicon in [true, false] {
            let notes = [
                IntelList.unreadFolders(count: 1, onAppleSilicon: onAppleSilicon),
                IntelList.unreadFolders(count: 2, onAppleSilicon: onAppleSilicon),
                IntelList.unreadJobFiles(count: 1, onAppleSilicon: onAppleSilicon),
                IntelList.unreadJobFiles(count: 2, onAppleSilicon: onAppleSilicon),
            ]
            for note in notes {
                #expect(note.key.contains("Rosetta") == onAppleSilicon, "\(note.key)")
            }
        }
    }
}
