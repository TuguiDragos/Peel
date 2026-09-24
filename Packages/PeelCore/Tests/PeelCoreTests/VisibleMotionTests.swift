@testable import PeelCore
import Testing

/// Which of the face's frames are worth sending to the screen. Every frame costs WindowServer the same, however
/// little moved, so a frame goes out only once some point has moved a tenth of a pixel.
struct VisibleMotionTests {
    private let square: [SIMD2<Double>] = [[0, 0], [30, 0], [30, 30], [0, 30]]

    private func moved(_ points: [SIMD2<Double>], by offset: SIMD2<Double>) -> [SIMD2<Double>] {
        points.map { $0 + offset }
    }

    @Test func sendsTheFirstFrame() {
        var motion = VisibleMotion()

        let sent = motion.isWorthAFrame(square, pixelsPerPoint: 1)

        #expect(sent)
    }

    @Test func holdsBackAFrameWhereNothingMovedATenthOfAPixel() {
        var motion = VisibleMotion()
        motion.isWorthAFrame(square, pixelsPerPoint: 1)

        let same = motion.isWorthAFrame(square, pixelsPerPoint: 1)
        let nearly = motion.isWorthAFrame(moved(square, by: [0.09, 0]), pixelsPerPoint: 1)

        #expect(!same)
        #expect(!nearly)
    }

    @Test func sendsAFrameWhereOnePointMovedATenthOfAPixel() {
        var motion = VisibleMotion()
        motion.isWorthAFrame(square, pixelsPerPoint: 1)
        var blinked = square
        blinked[2].y -= 0.1

        let sent = motion.isWorthAFrame(blinked, pixelsPerPoint: 1)

        #expect(sent)
    }

    /// Breathing moves the face a hundredth of a pixel a frame, so each frame is compared with the last frame
    /// sent, not the one before it. Otherwise a slow move would never be sent at all.
    @Test func sendsOnceSmallMovesAddUpToATenthOfAPixel() {
        var motion = VisibleMotion()
        motion.isWorthAFrame(square, pixelsPerPoint: 1)
        var sent: [Int] = []

        for step in 1...20 where motion.isWorthAFrame(moved(square, by: [0.03 * Double(step), 0]), pixelsPerPoint: 1) {
            sent.append(step)
        }

        #expect(sent == [4, 8, 12, 16, 20])
    }

    /// On a Retina display a tenth of a pixel is a twentieth of a point.
    @Test func measuresInPixelsOfTheDisplayItIsOn() {
        var standard = VisibleMotion()
        var retina = VisibleMotion()
        standard.isWorthAFrame(square, pixelsPerPoint: 1)
        retina.isWorthAFrame(square, pixelsPerPoint: 2)

        let onStandard = standard.isWorthAFrame(moved(square, by: [0, 0.06]), pixelsPerPoint: 1)
        let onRetina = retina.isWorthAFrame(moved(square, by: [0, 0.06]), pixelsPerPoint: 2)

        #expect(!onStandard)
        #expect(onRetina)
    }

    @Test func sendsAFrameOfAnotherShape() {
        var motion = VisibleMotion()
        motion.isWorthAFrame(square, pixelsPerPoint: 1)

        let sent = motion.isWorthAFrame(Array(square.prefix(3)), pixelsPerPoint: 1)

        #expect(sent)
    }
}
