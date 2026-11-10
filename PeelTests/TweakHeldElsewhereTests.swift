import Foundation
@testable import Peel
import PeelCore
import Testing

struct TweakHeldElsewhereTests {
    /// The row shows a lock and three words, so its note says who set the value and why the switch can't change it.
    @Test func eachPlaceSaysWhyTheSwitchCantBeUsed() {
        let places: [TweakState.Elsewhere] = [.thisMac, .everyAccount, .everyApp]

        #expect(Set(places.map(\.why.key)).count == places.count)
        for place in places {
            #expect(place.why.key != place.words.key, "\(place)")
        }
    }
}
