import Foundation
@testable import Peel
import Testing

struct HomebrewExclusionRefusalTests {
    @Test func theRefusalSaysPeelCouldNotLookInside() {
        #expect(HomebrewLibrary.cantLookInside.key.hasPrefix("Peel could not look inside the folders of this package"))
    }
}
