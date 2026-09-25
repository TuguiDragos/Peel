import Foundation
@testable import PeelCore
import Testing

struct SurpriseTests {
    private let frame = 1.0 / 120

    private func stepped(_ seconds: Double, _ surprise: inout Surprise) {
        for _ in 0..<Int((seconds / frame).rounded()) {
            surprise.advance(by: frame)
        }
    }

    /// The eyes open wide at once and settle back, while the head rises and comes down.
    @Test func theEyesOpenWideAndTheHeadRises() {
        var surprise = Surprise()
        #expect(surprise.widen == 0)
        #expect(surprise.rise == 0)

        stepped(0.42, &surprise)
        #expect(abs(surprise.widen - 0.28) < 0.001, "the eyes are widest at the peak")
        stepped(0.18, &surprise)
        #expect(abs(surprise.rise - 3) < 0.001, "the head is highest at the peak")

        stepped(0.66, &surprise)
        #expect(surprise.widen == 0)
        #expect(surprise.rise == 0)
    }

    /// Two quick blinks, then the eyes stay open.
    @Test func blinksTwice() {
        var surprise = Surprise()
        var closings = 0
        var wasShut = false
        for _ in 0..<Int((Surprise.duration / frame).rounded()) {
            surprise.advance(by: frame)
            let isShut = surprise.openness < 0.5
            if isShut, !wasShut { closings += 1 }
            wasShut = isShut
        }
        #expect(closings == 2)
        #expect(surprise.openness == 1)
    }

    /// The dot pops up at the top right as the look reaches it, stays while the face looks, and is gone at the end.
    @Test func looksAtTheDotWhileItShows() {
        var surprise = Surprise()
        stepped(0.7, &surprise)
        #expect(surprise.look == 0)
        #expect(surprise.dot == 0)

        stepped(0.4, &surprise)
        #expect(surprise.look == 1)
        #expect(surprise.dot == 1)

        stepped(1.35, &surprise)
        #expect(surprise.look == 0)
        #expect(surprise.dot == 0)
        #expect(surprise.isOver)
    }

    /// The smile comes once the dot has been seen, and has time to leave before the surprise is over.
    @Test func smilesAtTheEnd() {
        var surprise = Surprise()
        stepped(1.45, &surprise)
        #expect(!surprise.wantsHappyPose)
        stepped(0.1, &surprise)
        #expect(surprise.wantsHappyPose)
        stepped(0.5, &surprise)
        #expect(!surprise.wantsHappyPose)
        #expect(!surprise.isOver, "over before the smile had time to leave")
    }

    /// Time is counted in the steps the face takes, so a face that rested while Peel was in the background goes
    /// on from where it stopped.
    @Test func onlyTheFacesOwnStepsCount() {
        var surprise = Surprise()
        stepped(1, &surprise)
        let look = surprise.look
        surprise.advance(by: 0)
        surprise.advance(by: -5)
        #expect(surprise.look == look)
        #expect(!surprise.isOver)
    }
}
