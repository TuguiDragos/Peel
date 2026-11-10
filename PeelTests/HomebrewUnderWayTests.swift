import Foundation
@testable import Peel
import Testing

struct HomebrewUnderWayTests {
    /// Forget Cask is Peel's own work: Homebrew doesn't run while a cask's record goes to the Trash.
    @Test func forgettingACaskIsNotCalledRunningHomebrew() {
        #expect(HomebrewDetailView.underWay(isForgetting: true, homebrewRunsForIt: false)?.key == "Forgetting…")
        #expect(HomebrewDetailView.underWay(isForgetting: false, homebrewRunsForIt: true)?.key == "Running Homebrew…")
        #expect(HomebrewDetailView.underWay(isForgetting: false, homebrewRunsForIt: false) == nil)
    }
}
