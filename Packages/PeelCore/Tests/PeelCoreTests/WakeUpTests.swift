import Foundation
@testable import PeelCore
import Testing

struct WakeUpTests {
    private func near(_ value: Double, _ expected: Double, within tolerance: Double = 0.000_001) -> Bool {
        abs(value - expected) < tolerance
    }

    @Test func opensItsEyesThenLooksLeftAndRightWithTheStickerTurningAMomentLater() {
        #expect(near(WakeUp(elapsed: 0).presence, 0))
        #expect(near(WakeUp(elapsed: 0.25).openness, 1))
        let glancing = WakeUp(elapsed: 0.36)
        #expect(glancing.look < -5)
        #expect(abs(glancing.turn) < 0.2)
        #expect(near(WakeUp(elapsed: 0.55).look, -9))
        #expect(WakeUp(elapsed: 0.55).turn < -0.9)
        #expect(near(WakeUp(elapsed: 0.98).look, 7))
        #expect(WakeUp(elapsed: 0.98).turn > 0.6)
    }

    @Test func looksAtYouSurprisedJumpsAndBlinksTwice() {
        let surprised = WakeUp(elapsed: 1.35)
        #expect(near(surprised.look, 0))
        #expect(surprised.hop > 4.4)
        #expect(surprised.widen > 0.2)
        #expect(WakeUp(elapsed: 1.435).openness < 0.1)
        #expect(WakeUp(elapsed: 1.655).openness < 0.1)
    }

    @Test func smilesWithBothEyesAndBlushesThenWinksWithTheRightOne() {
        let smiling = WakeUp(elapsed: 2.4)
        #expect(smiling.left == WakeUp.Eye(closed: 1, bend: 1, lift: 1.2))
        #expect(smiling.right == WakeUp.Eye(closed: 1, bend: 1, lift: 1.2))
        #expect(near(smiling.blush, 0.6))
        #expect(near(smiling.tilt, -5, within: 0.15))
        let looking = WakeUp(elapsed: 2.8)
        #expect(looking.left == WakeUp.Eye())
        #expect(looking.right == WakeUp.Eye())
        let winking = WakeUp(elapsed: 3.3)
        #expect(winking.right == WakeUp.Eye(closed: 1, bend: 1, lift: 0.8))
        #expect(near(winking.left.closed, 0.1))
        #expect(winking.tilt > 3.4 && winking.tilt < 4.6)
    }

    @Test func dozesOffAndTheStickerSettlesBackWhereItBegan() {
        #expect(WakeUp(elapsed: 4.8).openness < 0.1)
        #expect(near(WakeUp(elapsed: 4.8).presence, 1))
        #expect(WakeUp(elapsed: 4.8).tilt < -1)
        let end = WakeUp(elapsed: 5.6)
        #expect(near(end.presence, 0) && near(end.hop, 0) && near(end.tilt, 0) && near(end.shift, 0))
        #expect(near(end.squash, 0) && near(end.breath, 0))
        #expect(!WakeUp(elapsed: 5.59).isOver)
        #expect(end.isOver)
    }

    @Test func nothingJumpsFromOneFrameToTheNextEvenAt240FramesASecond() {
        var before = WakeUp(elapsed: 0)
        for frame in 1...Int(5.6 * 240) {
            let now = WakeUp(elapsed: Double(frame) / 240)
            let steps: [(String, Double, Double)] = [
                ("look", now.look - before.look, 1.5), ("turn", now.turn - before.turn, 0.1),
                ("openness", now.openness - before.openness, 0.2), ("widen", now.widen - before.widen, 0.05),
                ("blush", now.blush - before.blush, 0.02), ("hop", now.hop - before.hop, 0.3),
                ("squash", now.squash - before.squash, 0.02), ("tilt", now.tilt - before.tilt, 0.6),
                ("shift", now.shift - before.shift, 0.15), ("presence", now.presence - before.presence, 0.08),
                ("left", now.left.closed - before.left.closed, 0.2), ("right", now.right.closed - before.right.closed, 0.2),
                ("bend", now.right.bend - before.right.bend, 0.1), ("lift", now.right.lift - before.right.lift, 0.1),
            ]
            for (name, step, most) in steps {
                #expect(abs(step) <= most, "\(name) moves \(step) at frame \(frame)")
            }
            before = now
        }
    }

    @Test func underReduceMotionTheWinkingFaceOnlyFadesInAndOut() {
        for elapsed in stride(from: 0.0, through: 2.3, by: 0.1) {
            let still = WakeUp(elapsed: elapsed, reducingMotion: true)
            #expect(still.look == 0 && still.turn == 0 && still.hop == 0 && still.squash == 0 && still.tilt == 0)
            #expect(still.widen == 0 && still.breath == 0 && still.shift == 0)
            #expect(still.left == WakeUp.Eye() && still.right == WakeUp.Eye(closed: 1, bend: 1))
        }
        #expect(near(WakeUp(elapsed: 1, reducingMotion: true).presence, 1))
        #expect(WakeUp(elapsed: 2.3, reducingMotion: true).isOver)
    }
}

struct SquashTests {
    @Test func squashesThenStretchesAndComesToRest() {
        var squash = Squash()
        squash.press(at: 10, count: 1)
        #expect(squash.amount(at: 10.06) < -0.02)
        #expect(squash.amount(at: 10.19) > 0.005)
        #expect(squash.amount(at: 10.8) == 0)
        #expect(!squash.isOver(at: 10.79))
        #expect(squash.isOver(at: 10.8))
    }

    @Test func eachClickPressesHarderAndLeansTheOtherWay() {
        var first = Squash(), second = Squash(), fifth = Squash()
        first.press(at: 0, count: 1)
        second.press(at: 0, count: 2)
        fifth.press(at: 0, count: 5)
        #expect(fifth.amount(at: 0.06) < first.amount(at: 0.06))
        #expect(first.tilt(at: 0.06) < 0)
        #expect(second.tilt(at: 0.06) > 0)
    }

    @Test func aClickWhileItSwingsAddsToTheSwingWithoutAJump() {
        var squash = Squash()
        squash.press(at: 10, count: 1)
        let amount = squash.amount(at: 10.12), tilt = squash.tilt(at: 10.12)
        #expect(amount != 0 && tilt != 0)
        squash.press(at: 10.12, count: 2)
        #expect(squash.amount(at: 10.12) == amount)
        #expect(squash.tilt(at: 10.12) == tilt)
        #expect(!squash.isOver(at: 10.85))
        #expect(squash.isOver(at: 10.93))
    }
}
