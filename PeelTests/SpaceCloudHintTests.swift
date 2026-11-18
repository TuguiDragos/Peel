import Foundation
@testable import Peel
import PeelCore
import Testing

struct SpaceCloudHintTests {
    /// The iCloud Drive page selects whole folders and removes every selected download at once.
    @Test func theHintNamesWhatTheCloudPageDoes() throws {
        let hint = try #require(SpaceItem.words(for: "icloud")?.hint).key

        #expect(hint.hasPrefix("The iCloud Drive page in Peel removes the downloads of files of"), "\(hint)")
    }
}
