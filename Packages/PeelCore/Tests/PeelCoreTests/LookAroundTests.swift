import Foundation
@testable import PeelCore
import Testing

/// Tests `LookAround`: while the pointer is outside the window, the face at the head of the sidebar looks all
/// around by itself, slowly.
struct LookAroundTests {
    private let wentLeft = LookAround.Moment(aim: [-1, 0], hold: 1)
    private let starts: [LookAround.Moment] = [
        LookAround.Moment(aim: [-1, 0], hold: 1),
        LookAround.Moment(aim: [0.6, -0.8], hold: 1),
        LookAround.Moment(aim: [0, 0.5], hold: 0.4),
        LookAround.Moment(aim: .zero, hold: 0),
    ]

    @Test func keepsLookingWhereThePointerWentForAMoment() {
        let around = LookAround(from: wentLeft)
        for elapsed in stride(from: 0.0, through: 0.9, by: 0.05) {
            #expect(around.moment(after: elapsed) == wentLeft)
        }
    }

    /// A place counts once the face stays on it for a second: passing through a direction is not looking there.
    @Test func thenLooksEveryWayAndBackAtWhoeverIsInFront() {
        let around = LookAround(from: wentLeft)
        var ways = Set<Int>()
        var rested = false
        for elapsed in stride(from: 1.0, through: 200, by: 0.05) {
            let moment = around.moment(after: elapsed)
            guard moment == around.moment(after: elapsed + 1) else { continue }
            if moment == LookAround.Moment(aim: .zero, hold: 0) { rested = true }
            guard moment.hold == 1, length(moment.aim) >= 0.5 else { continue }
            let angle = atan2(moment.aim.y, moment.aim.x) + .pi / 8 + 2 * .pi
            ways.insert(Int(angle.truncatingRemainder(dividingBy: 2 * .pi) / (.pi / 4)))
        }
        #expect(ways == Set(0..<8))
        #expect(rested)
    }

    /// The face moves slowly and never jumps: a look all the way across takes at least a second, and the first
    /// look starts from wherever the face was looking when the pointer left.
    @Test func movesSlowlyWithoutAJumpFromWhereverItLooked() {
        for start in starts {
            let around = LookAround(from: start)
            var last = around.moment(after: 0)
            var fastest = 0.0
            var fastestHold = 0.0
            #expect(last == start)
            for step in 1...50_000 {
                let now = around.moment(after: Double(step) * 0.002)
                fastest = max(fastest, length(now.aim - last.aim) / 0.002)
                fastestHold = max(fastestHold, abs(now.hold - last.hold) / 0.002)
                last = now
            }
            #expect(fastest > 0)
            #expect(fastest <= 2)
            #expect(fastestHold <= 1.25 + 1e-9)
        }
    }

    /// Each place is held long enough to be seen, and none for so long that the face looks stuck.
    @Test func holdsEachPlaceAndThenMovesOn() {
        let around = LookAround(from: wentLeft)
        var runs: [Double] = []
        var run = 0.0
        var last = around.moment(after: 1.5)
        for step in 1...20_000 {
            let now = around.moment(after: 1.5 + Double(step) * 0.01)
            if now == last {
                run += 0.01
            } else if run > 0 {
                runs.append(run)
                run = 0
            }
            last = now
        }
        let held = runs.dropFirst()
        #expect(held.count > 10)
        #expect((held.min() ?? 0) >= 1.2)
        #expect((held.max() ?? .infinity) <= 3)
    }

    @Test func neverLooksFurtherThanTheFaceCan() {
        for start in starts {
            let around = LookAround(from: start)
            let moments = (0...20_000).map { around.moment(after: Double($0) * 0.01) }
            #expect(moments.map { length($0.aim) }.max()! <= 1 + 1e-9)
            #expect(moments.allSatisfy { (0...1).contains($0.hold) })
        }
    }

    private func length(_ vector: SIMD2<Double>) -> Double {
        (vector * vector).sum().squareRoot()
    }
}
