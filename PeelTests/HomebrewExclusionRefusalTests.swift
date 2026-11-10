import Foundation
@testable import Peel
import Testing

struct HomebrewExclusionRefusalTests {
    /// The label beside a stopped Uninstall says why Peel couldn't check the package.
    @Test func theRefusalSaysPeelCouldNotLookInside() {
        #expect(HomebrewLibrary.cantLookInside.key.hasPrefix("Peel couldn’t look inside this package’s folders"))
    }
}
