import Foundation
@testable import Peel
import PeelCore
import Testing

@MainActor
struct SpokenTotalTests {
    @Test func saysWhatAScanFoundToMoveAsThePagesHeaderSaysIt() {
        #expect(SizeTotal(known: 0, isComplete: true).spoken == nil)
        #expect(SizeTotal(known: 0, isComplete: false).spoken.map { String($0.characters) } == "Unknown can be moved to the Trash")
        let total = SizeTotal(known: 2_000_000, isComplete: true)
        #expect(total.spoken.map { String($0.characters) } == "\(total.text) can be moved to the Trash")
    }
}
