import Foundation
@testable import Peel
import Testing

struct VulnerabilitiesNoteTests {
    /// Homebrew checks the current formula when it can't tell what the installed one was built from.
    @Test func theNoteDoesNotSayWhichVersionWasChecked() {
        let note = HomebrewVulnerabilitySections.howHomebrewChecked.key

        #expect(note.hasPrefix("Homebrew checked this formula against OSV.dev"), "\(note)")
    }
}
