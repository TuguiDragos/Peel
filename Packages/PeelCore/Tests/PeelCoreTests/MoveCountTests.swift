import Foundation
@testable import PeelCore
import Testing

struct MoveCountTests {
    @Test func aRemovalSaysWhileItReadsWhatItWillMove() async {
        let count = MoveCount()

        let whileReading = await MoveCount.$current.withValue(count) {
            await MoveCount.reading { count.isReading }
        }

        #expect(whileReading)
        #expect(!count.isReading)
    }
}
