import Foundation
@testable import Peel
import Testing

struct PrivacyWordsTests {
    /// The App Store is asked about every app installed from it, free ones too.
    @Test func thePaneSaysWhichAppsTheAppStoreIsAskedAboutAndWhereUpgradeIs() {
        #expect(PrivacySettingsView.whatPeelSends.key.contains("the App Store for an app installed from it"))
        #expect(PrivacySettingsView.homebrewGoesOnlineWhenAsked.key.contains("Upgrade (on the Homebrew page or on an app’s own page)"))
    }
}
