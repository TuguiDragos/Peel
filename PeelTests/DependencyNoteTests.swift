import Foundation
@testable import Peel
import Testing

struct DependencyNoteTests {
    /// Homebrew notes why it installed a formula, not whether anything still needs it, which Clean Up says.
    @Test func theBadgeSaysWhyHomebrewInstalledItNotThatSomethingNeedsIt() {
        #expect(HomebrewDetailView.dependencyNote.key.contains("for another package, not because you asked for it"))
    }
}
