import Foundation
@testable import Peel
import PeelCore
import Testing

@MainActor
struct HomebrewCountTests {
    @Test func countsNothingBeforeHomebrewSaidWhatIsInstalled() {
        let homebrew = HomebrewLibrary()

        #expect(homebrew.count(of: .formula) == nil)
        #expect(homebrew.count(of: .cask) == nil)
    }
}
