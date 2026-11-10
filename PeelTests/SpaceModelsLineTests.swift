import Foundation
@testable import Peel
import PeelCore
import Testing

struct SpaceModelsLineTests {
    /// The figure counts only the model folders the Developer page knows, never every model on the Mac.
    @Test func eachSentenceSaysItCountsWhatDeveloperLists() {
        for reading in [SizeTotal.Reading.exactly(1_000), .atLeast(1_000), .unknown] {
            let sentence = SpaceList.modelsSentence(reading).key
            #expect(sentence.contains("AI models and datasets the Developer page lists"), "\(sentence)")
        }
    }
}
