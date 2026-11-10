import Foundation
@testable import Peel
import Testing

struct PackageQuitTitleTests {
    /// The button already says Quit Apps for several, and "it" is wrong for them in every language.
    @Test func severalAppsAreAskedInThePlural() {
        #expect(PackageDetailView.quitTitle(names: "Alpha and Beta", several: true).key == "Quit these apps before removing them.")
        #expect(PackageDetailView.quitTitle(names: "Alpha", several: false).key == "Quit %@ before removing it.")
    }
}
