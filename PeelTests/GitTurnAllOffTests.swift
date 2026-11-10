import Foundation
@testable import Peel
import Testing

struct GitTurnAllOffTests {
    /// Turning a Git setting off removes it when the person set it, which nothing brings back, so both say so.
    @Test func bothSayWhatHappensToSettingsYouMadeYourself() {
        #expect(GitTab.turningOneOff.key.hasSuffix("or removes it when you had set it yourself."))
        #expect(GitTab.afterTurningAllOff.key.contains("Settings you made yourself that are on here are removed"))
    }
}
