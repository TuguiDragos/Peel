@testable import PeelCore
import Testing

/// Checks the hitch counter's arithmetic by reading the lines of its report.
struct HitchesTests {
    @Test func countsEveryTurnTheLongestAndThoseLongerThanAFrame() {
        var hitches = Hitches()
        hitches.frame(at: 0, due: 0.010)
        for seconds in [0.002, 0.004, 0.1205, 0.009, 0.011] {
            hitches.turn(lasting: seconds)
        }

        #expect(hitches.report.first == "run loop: 5 turns, longest 120.5 ms, 2 over one frame")
    }

    @Test func saysWhetherATurnWasLongerThanAFrame() {
        var hitches = Hitches()
        hitches.frame(at: 0, due: 0.010)

        let short = hitches.turn(lasting: 0.009)
        let long = hitches.turn(lasting: 0.011)

        #expect(!short)
        #expect(long)
    }

    /// Until the display has said how often it asks, a frame is a sixtieth of a second, the slowest a Mac's
    /// display runs.
    @Test func beforeTheDisplayHasAskedAFrameIsASixtiethOfASecond() {
        var hitches = Hitches()
        hitches.turn(lasting: 0.016)
        hitches.turn(lasting: 0.017)

        #expect(hitches.report.first == "run loop: 2 turns, longest 17.0 ms, 1 over one frame")
    }

    /// A gap of 127.7 ms at 10 ms a frame counts as twelve missed frames.
    @Test func countsTheFramesAGapLeftOut() {
        var hitches = Hitches()
        for timestamp in [0, 0.010, 0.020, 0.1477, 0.1577] {
            hitches.frame(at: timestamp, due: timestamp + 0.010)
        }

        #expect(hitches.report.last == "frames: 5 callbacks, period 10.00 ms, worst gap 127.7 ms, 12 missed")
    }

    /// A display that slows down when little moves asks less often, and the longer gap is not a missed frame.
    @Test func aDisplayThatSlowsDownMissesNothing() {
        var hitches = Hitches()
        hitches.frame(at: 0, due: 0.00833)
        hitches.frame(at: 0.00833, due: 0.01667)
        hitches.frame(at: 0.025, due: 0.04167)

        #expect(hitches.report.last == "frames: 3 callbacks, period 8.33 ms, worst gap 16.7 ms, 0 missed")
    }

    @Test func aWindowTheDisplayNeverAskedForSaysSo() {
        #expect(Hitches().report == ["run loop: 0 turns, longest 0.0 ms, 0 over one frame", "frames: 0 callbacks"])
    }
}
