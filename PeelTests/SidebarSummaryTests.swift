import Foundation
@testable import Peel
import Testing

struct SidebarSummaryTests {
    private func english(_ resource: LocalizedStringResource) -> String {
        var resource = resource
        resource.locale = Locale(identifier: "en")
        return String(localized: resource)
    }

    @Test func saysHowManyToolsAreOffWithTheVerbAgreeing() {
        #expect(english(GeneralSettingsView.sidebarSummary(hidden: 0)) == "Every tool is in the sidebar.")
        #expect(english(GeneralSettingsView.sidebarSummary(hidden: 1)) == "1 more tool is available.")
        #expect(english(GeneralSettingsView.sidebarSummary(hidden: 6)) == "6 more tools are available.")
    }
}
