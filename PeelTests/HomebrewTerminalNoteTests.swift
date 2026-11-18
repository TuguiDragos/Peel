import Foundation
@testable import Peel
import Testing

@MainActor
struct HomebrewTerminalNoteTests {
    @Test func saysWhoRunsASudoCommandOnAnAccountThatIsNotAnAdministrators() {
        #expect(HomebrewDetailView.needsTerminal(isAdministrator: true).count == 1)
        let said = HomebrewDetailView.needsTerminal(isAdministrator: false)
        #expect(said.count == 2)
        #expect(said.last?.key.contains("is not an administrator") == true)
    }
}
