import Foundation

/// How About's icon gives under clicks: each one squashes it like a soft sticker pressed with a finger, and it springs
/// back, each click in a row a little harder and leaning the other way. A click while the icon still swings adds its
/// push to the swing, as pushes on a spring do, rather than starting it again from rest.
public struct Squash: Sendable {
    /// How long one click's swing lasts, in seconds.
    public static let duration = 0.8

    private var presses: [Press] = []

    public init() {}

    /// Adds the `count`th click in a row, made at `time`, in seconds.
    public mutating func press(at time: Double, count: Int) {
        presses.removeAll { time - $0.time >= Self.duration }
        presses.append(Press(time: time, count: count))
    }

    /// How the icon squashes (below 0) or stretches (above 0) at `time`, as a fraction of its height.
    public func amount(at time: Double) -> Double {
        presses.reduce(0) { $0 - (0.05 + 0.012 * Double($1.count - 1)) * $1.wave(at: time) }
    }

    /// How far the icon leans at `time`, in degrees, clockwise: left on odd clicks, right on even ones.
    public func tilt(at time: Double) -> Double {
        presses.reduce(0) { $0 + ($1.count % 2 == 1 ? -2.2 : 2.2) * $1.wave(at: time) }
    }

    /// Whether every click's swing has died away by `time`.
    public func isOver(at time: Double) -> Bool {
        presses.allSatisfy { time - $0.time >= Self.duration }
    }

    private struct Press: Sendable {
        let time: Double
        let count: Int

        /// A spring's swing, starting at rest and dying away.
        func wave(at now: Double) -> Double {
            let elapsed = now - time
            guard elapsed > 0, elapsed < Squash.duration else { return 0 }
            return exp(-elapsed / 0.14) * sin(2 * .pi * elapsed / 0.26)
        }
    }
}
