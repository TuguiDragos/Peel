import Foundation

/// The face's surprise when a new version of Peel is out. Its eyes open wide and blink twice while it rises a
/// little, then it looks up to the right, where a red dot pops up like a badge, and it smiles once it has seen it.
/// Each value below is how far into one part of that the face is, at the time counted so far. Time is counted in the
/// steps the face takes, never read from the clock, so a face that rested while Peel was in the background goes on
/// from where it stopped.
public struct Surprise: Sendable {
    /// How long the whole surprise takes, in seconds.
    public static let duration = 2.4
    /// Where the face looks while the dot shows: up and to the right, where the dot is.
    public static let aim = (x: 0.71, y: -0.71)

    private var elapsed = 0.0

    public init() {}

    public mutating func advance(by step: Double) {
        elapsed += max(0, step)
    }

    public var isOver: Bool {
        elapsed >= Self.duration
    }

    /// How much wider the eyes are than usual, as a fraction of their size.
    public var widen: Double {
        0.28 * bump(from: 0, to: 0.84)
    }

    /// How far the head rises, in the face's units, which are a hundredth of its width.
    public var rise: Double {
        3 * bump(from: 0, to: 1.2)
    }

    /// How open the eyes are, 1 when fully open, through the two quick blinks.
    public var openness: Double {
        1 - 0.9 * max(bump(from: 0.288, to: 0.48), bump(from: 0.528, to: 0.72))
    }

    /// How far the look has gone toward the dot, from 0 to 1.
    public var look: Double {
        ramp(from: 0.72, to: 1.008) * (1 - ramp(from: 1.92, to: 2.28))
    }

    /// The dot's size, from 0 to its full size, 1. It grows quickly and then slows as it reaches full size.
    public var dot: Double {
        let growing = ramp(from: 0.72, to: 0.96)
        let slowing = elapsed < 0.96 ? 1.25 - 0.25 * ramp(from: 0.816, to: 0.96) : 1
        return min(1, growing * slowing) * (1 - ramp(from: 2.16, to: 2.4))
    }

    /// Whether the face should give its happy pose, which is how the surprise ends: the smile arrives, holds, and
    /// has time to leave before the surprise is over.
    public var wantsHappyPose: Bool {
        elapsed >= 1.49 && elapsed < 2.0
    }

    /// 0 before `start`, 1 after `end`, and in a straight line between.
    private func ramp(from start: Double, to end: Double) -> Double {
        min(1, max(0, (elapsed - start) / (end - start)))
    }

    /// 0 outside `start` to `end`, rising to 1 at the middle and falling back, as half a sine wave.
    private func bump(from start: Double, to end: Double) -> Double {
        let progress = ramp(from: start, to: end)
        return progress > 0 && progress < 1 ? sin(.pi * progress) : 0
    }
}
