import Foundation
@testable import Peel
import Testing

@MainActor
struct HomebrewUpgradeWarningTests {
    @Test func anAppsPagePromisesNoProgressOrStopItDoesNotShow() {
        let onAnAppsPage = HomebrewUpgradeWarning.sentences(deletesAnApp: true, on: .appPage).map(\.key)
        let onTheHomebrewPage = HomebrewUpgradeWarning.sentences(deletesAnApp: true, on: .homebrewPage).map(\.key)

        #expect(onAnAppsPage == [HomebrewUpgradeWarning.deletesTheApp.key])
        #expect(onTheHomebrewPage == [HomebrewUpgradeWarning.takesLong.key, HomebrewUpgradeWarning.deletesTheApp.key])
        #expect(
            HomebrewUpgradeWarning.sentences(deletesAnApp: false, on: .homebrewPage).map(\.key)
                == [HomebrewUpgradeWarning.takesLong.key]
        )
    }
}
