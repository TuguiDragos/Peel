@testable import PeelCore
import Testing

struct ScannedRevisionsTests {
    /// A change to the exclusions reaches a page only through a scan that runs under the new list. A page's
    /// first question must count as its first scan, or no later question would ever ask for a rescan.
    @Test func aPageScansAgainOnceTheListHasChanged() {
        var revisions = ScannedRevisions()
        let asked = [
            revisions.needsRescan("Orphans", at: 1),
            revisions.needsRescan("Orphans", at: 1),
            revisions.needsRescan("Orphans", at: 2),
            revisions.needsRescan("Orphans", at: 2),
            revisions.needsRescan("Space", at: 2),
            revisions.needsRescan("Space", at: 5),
        ]

        // Orphans: its first scan, a return with nothing changed, then a change that asks for one rescan only.
        // Space: its first visit, then its change.
        #expect(asked == [false, false, true, false, false, true])
    }
}
