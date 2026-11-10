import Foundation
@testable import Peel
import PeelCore
import Testing

@MainActor
struct SavedSettingsHelpTests {
    /// The button is in Settings, so its help names the tab to go to, and says why it can't put the settings back.
    @Test func thePutBackHelpNamesTheExclusionsTabAndWhy() {
        let excluded = SavedSettingsSection.putBackHelp(
            refusal: .excluded, exclusionsUnreadable: false, isOpen: false, name: "Example"
        )
        let unreadable = SavedSettingsSection.putBackHelp(
            refusal: .exclusionsNotKnown, exclusionsUnreadable: true, isOpen: false, name: "Example"
        )

        for help in [excluded, unreadable] {
            #expect(help.contains("Exclusions tab"), "\(help)")
            #expect(!help.contains("in Settings"), "\(help)")
        }
        #expect(excluded.contains("is excluded"))
        #expect(unreadable.contains("can’t read your exclusions"))
    }
}
