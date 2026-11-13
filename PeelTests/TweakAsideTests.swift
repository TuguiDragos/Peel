import Foundation
@testable import Peel
import PeelCore
import Testing

struct TweakAsideTests {
    @Test func theScreenshotFolderSaysWhereScreenshotsGoInstead() {
        let destinations: [ScreenshotDestination] = [.clipboard, .preview, .mail, .messages, .unknown]
        let said = destinations.map { String(localized: $0.instead) }
        #expect(Set(said).count == 5)
        #expect(said.allSatisfy { $0.contains("Save to") })
    }

    /// A shortcut and a reassurance are no warnings, so they read in the note without the caution's mark.
    @Test func aTipIsNoCaution() throws {
        for id in ["finder-hidden-files", "dock-static-only"] {
            let words = try #require(Tweak.words(for: id))
            #expect(words.caution == nil && words.aside != nil, "\(id)")
        }
    }
}
