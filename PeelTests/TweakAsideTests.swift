import Foundation
@testable import Peel
import PeelCore
import Testing

struct TweakAsideTests {
    /// A shortcut and a reassurance are no warnings, so they read in the note without the caution's mark.
    @Test func aTipIsNoCaution() throws {
        for id in ["finder-hidden-files", "dock-static-only"] {
            let words = try #require(Tweak.words(for: id))
            #expect(words.caution == nil && words.aside != nil, "\(id)")
        }
    }
}
