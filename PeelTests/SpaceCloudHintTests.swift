import Foundation
@testable import Peel
import PeelCore
import Testing

struct SpaceCloudHintTests {
    /// The iCloud Drive page selects whole folders and removes every selected download at once.
    @Test func theHintNamesWhatTheCloudPageDoes() throws {
        let words = try #require(SpaceItem.words(for: "icloud"))

        #expect(words.hint?.key == "The iCloud Drive page in Peel")
        #expect(words.hintNote?.key.hasPrefix("It removes the downloads of files of") == true)
    }
}
