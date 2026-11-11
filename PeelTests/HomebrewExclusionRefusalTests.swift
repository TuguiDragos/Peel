import Foundation
@testable import Peel
import Testing

struct HomebrewExclusionRefusalTests {
    @Test func theRefusalSaysPeelCouldNotLookInside() {
        #expect(HomebrewLibrary.cantLookInside.key.hasPrefix("Peel couldn’t look inside this package’s folders"))
    }
}
