import Foundation
@testable import Peel
import Testing

struct OrphanEmptyStateTests {
    /// The first words a new Mac shows on the page, so they name no identifiers and read one way.
    @Test func theEmptyPageSaysWhatShowsUpInPlainWords() {
        #expect(OrphanList.nothingYet.key.hasSuffix("files named for an app that isn’t installed, and files of apps Peel saw removed."))
    }
}
