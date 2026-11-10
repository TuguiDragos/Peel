import Foundation
@testable import Peel
import Testing

struct CloudSharedDownloadsTests {
    /// What matters comes first: these aren't listed, and removing one would free nothing.
    @Test func theNoteSaysFirstThatTheseAreNotListed() {
        #expect(CloudView.sharedDownloadsWords(3) == String(inflecting: "Not listed: ^[\(3) download](inflect: true) sharing space on disk with another copy on this Mac, such as the one iCloud keeps after an upload. Removing one would free nothing now."))
    }
}
