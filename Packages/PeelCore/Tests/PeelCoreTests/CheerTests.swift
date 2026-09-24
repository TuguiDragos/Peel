import Foundation
@testable import PeelCore
import Testing

struct CheerTests {
    private let frame = 1.0 / 120

    private func stepped(_ seconds: Double, _ cheer: inout Cheer) {
        for _ in 0..<Int((seconds / frame).rounded()) {
            cheer.advance(by: frame)
        }
    }

    /// The face smiles for as long as the smile takes to arrive and one beat more, then lets it go, and the
    /// cheer is over once the smile has had time to leave.
    @Test func smilesOnceThenLetsTheSmileGo() {
        var cheer = Cheer(rise: 0.3, hold: 0.32, fall: 0.4)
        #expect(cheer.wantsHappyPose)

        stepped(0.61, &cheer)
        #expect(cheer.wantsHappyPose, "the smile let go before it had held")
        stepped(0.02, &cheer)
        #expect(!cheer.wantsHappyPose)
        #expect(!cheer.isOver, "over before the smile had time to leave")

        stepped(0.4, &cheer)
        #expect(cheer.isOver)
    }

    /// Time is counted in the steps the face takes, so a face that rested while Peel was in the background
    /// goes on from where it stopped rather than having missed the smile.
    @Test func onlyTheFacesOwnStepsCount() {
        var cheer = Cheer(rise: 0.3, hold: 0.32, fall: 0.4)
        stepped(0.3, &cheer)
        cheer.advance(by: 0)

        #expect(cheer.wantsHappyPose)
        #expect(!cheer.isOver)
    }
}
