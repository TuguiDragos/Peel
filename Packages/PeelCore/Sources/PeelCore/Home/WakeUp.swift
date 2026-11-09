import Foundation

/// The face that wakes on the sticker of About's icon at the fifth click in a row: it opens its eyes, looks left,
/// then right, then at the person, surprised, smiles at them with its eyes and blushes, winks, dozes off, and the
/// sticker settles back in its place. Each value is worked out from the seconds since that click, as `Surprise` works
/// out the face's, so it is as smooth at any frame rate. Under Reduce Motion nothing moves: the winking face only
/// fades in and out.
public struct WakeUp: Sendable {
    /// One eye: how far it has closed (0 open, 1 closed), how far its closed line has bent up into an arch, and how
    /// far, in the face's units, a smile lifts it.
    public struct Eye: Sendable, Equatable {
        public var closed = 0.0
        public var bend = 0.0
        public var lift = 0.0

        public init(closed: Double = 0, bend: Double = 0, lift: Double = 0) {
            self.closed = closed
            self.bend = bend
            self.lift = lift
        }
    }

    public let elapsed: Double
    public let reducingMotion: Bool

    public init(elapsed: Double, reducingMotion: Bool = false) {
        self.elapsed = elapsed
        self.reducingMotion = reducingMotion
    }

    /// How long the whole scene takes, in seconds.
    public var duration: Double { reducingMotion ? 2.3 : 5.6 }

    public var isOver: Bool { elapsed >= duration }

    /// How much of the face shows, from 0 to 1.
    public var presence: Double {
        guard !reducingMotion else { return ramp(0, 0.25) * (1 - ramp(1.9, 2.3)) }
        return ramp(0.04, 0.10) * (1 - Curve.easeInOut(ramp(4.85, 5.30)))
    }

    /// Where the eyes look across, in the face's units: quick flicks, each held, as the face's own look moves.
    public var look: Double {
        guard !reducingMotion else { return 0 }
        return elapsed < 0.70 ? -9 * Curve.easeOut(ramp(0.30, 0.39))
            : elapsed < 1.10 ? -9 + 16 * Curve.easeOut(ramp(0.70, 0.80))
            : 7 - 7 * Curve.easeOut(ramp(1.10, 1.18))
    }

    /// How far the sticker turns after its eyes, from -1 left to about 0.8 right: a moment later, and swinging a
    /// little past each time, as a head follows a glance.
    public var turn: Double {
        guard !reducingMotion else { return 0 }
        return -spring(0.33, 0.34, 0.72) + 1.78 * spring(0.73, 0.34, 0.72) - 0.78 * spring(1.13, 0.34, 0.72)
    }

    /// How open both eyes are, 1 fully: waking, two quick blinks when surprised, and dozing off.
    public var openness: Double {
        guard !reducingMotion else { return 1 }
        let drowsy = elapsed < 4.20 ? 0.65 * Curve.easeInOut(ramp(3.95, 4.20))
            : elapsed < 4.35 ? 0.65 - 0.2 * Curve.easeInOut(ramp(4.20, 4.35))
            : 0.45 + 0.47 * Curve.easeInOut(ramp(4.35, 4.72))
        return min(0.08 + 0.92 * Curve.easeOut(ramp(0.08, 0.22)),
                   1 - 0.92 * max(blink(at: 1.38), blink(at: 1.60)),
                   1 - drowsy)
    }

    /// How much wider the eyes are than usual, as a fraction of their size: they pop open when the face is surprised.
    public var widen: Double {
        guard !reducingMotion else { return 0 }
        return 0.26 * spring(1.12, 0.24, 0.42) * (1 - Curve.easeInOut(ramp(1.70, 2.05)))
    }

    /// How red the cheeks are, from 0 to 1.
    public var blush: Double {
        guard !reducingMotion else { return 0 }
        return 0.6 * Curve.easeInOut(ramp(2.00, 2.35)) * (1 - Curve.easeInOut(ramp(3.70, 4.60)))
    }

    /// The left eye: it smiles with the right one, and narrows a little while the right one winks.
    public var left: Eye {
        guard !reducingMotion else { return Eye() }
        let squint = 0.1 * Curve.easeOut(ramp(2.90, 3.02)) * (1 - Curve.easeInOut(ramp(3.45, 3.62)))
        return Eye(closed: max(smiling.closed, squint), bend: smiling.bend, lift: smiling.lift)
    }

    public var right: Eye {
        guard !reducingMotion else { return Eye(closed: 1, bend: 1) }
        return Eye(closed: max(smiling.closed, winking.closed), bend: max(smiling.bend, winking.bend),
                   lift: max(smiling.lift, winking.lift))
    }

    /// How far the sticker jumps, in points of the 96 point icon: up in an arc when the face is surprised, a nod with
    /// the wink, a slow sink as it dozes, and its breath.
    public var hop: Double {
        guard !reducingMotion else { return 0 }
        let arc = (elapsed - 1.35) / 0.21
        let flight = abs(arc) < 1 ? 4.8 * (1 - arc * arc) : 0
        let breath = 0.35 * sin(2 * .pi * elapsed / 2.4) * presence
        return (flight - 0.7 * bump(2.90, 3.12) - Curve.easeInOut(ramp(3.95, 4.70))) * settling + breath
    }

    /// How far the sticker moves across with its turn, in points.
    public var shift: Double { 1.4 * turn * settling }

    /// How the sticker stretches (above 0) or squashes (below 0), as a fraction of its height: before and during the
    /// jump, on landing and back, and with the wink's nod.
    public var squash: Double {
        guard !reducingMotion else { return 0 }
        return -0.05 * bump(1.04, 1.16) + 0.045 * bump(1.14, 1.36) - 0.045 * bump(1.52, 1.66)
            + 0.015 * bump(1.64, 1.80) - 0.02 * bump(2.88, 3.04)
    }

    /// How much larger the sticker is as it breathes, as a fraction of its size.
    public var breath: Double {
        reducingMotion ? 0 : 0.01 * sin(2 * .pi * elapsed / 2.4 + .pi / 2) * presence
    }

    /// How far the sticker leans, in degrees, clockwise: with its turn, to the left while it smiles, a little more to
    /// the left before it swings right to wink, back up, then a little down as it dozes.
    public var tilt: Double {
        guard !reducingMotion else { return 0 }
        let leaning = 2.2 * turn - 5 * spring(1.95, 0.40, 0.62) - 1.2 * spring(2.80, 0.14, 0.9)
            + 10.2 * spring(2.88, 0.34, 0.55) - 4 * spring(3.60, 0.50, 0.85) - 2 * spring(4.00, 0.90, 1)
        return leaning * settling
    }

    /// Both eyes close as in a blink, bend up into arches and rise a little, then open again.
    private var smiling: Eye {
        Eye(closed: Curve.easeIn(ramp(1.95, 2.05)) * (1 - Curve.easeOut(ramp(2.60, 2.74))),
            bend: Curve.easeOut(ramp(2.01, 2.17)) * (1 - Curve.easeIn(ramp(2.54, 2.65))),
            lift: 1.2 * Curve.easeOut(ramp(2.05, 2.25)) * (1 - Curve.easeIn(ramp(2.52, 2.66))))
    }

    /// The right eye alone, quicker.
    private var winking: Eye {
        Eye(closed: Curve.easeIn(ramp(2.88, 2.94)) * (1 - Curve.easeInOut(ramp(3.62, 3.80))),
            bend: Curve.easeOut(ramp(2.92, 3.06)) * (1 - Curve.easeInOut(ramp(3.48, 3.68))),
            lift: 0.8 * Curve.easeOut(ramp(2.94, 3.10)) * (1 - Curve.easeInOut(ramp(3.46, 3.66))))
    }

    /// 1 while the sticker moves, falling to 0 once the face has faded, so it comes to rest where it began.
    private var settling: Double { 1 - Curve.easeInOut(ramp(4.95, 5.60)) }

    /// A blink that begins at `start`: the lid closes in 55 milliseconds and opens in 95, as eyes close quicker than
    /// they open.
    private func blink(at start: Double) -> Double {
        let time = elapsed - start
        guard time > 0, time < 0.15 else { return 0 }
        return time < 0.055 ? Curve.easeIn(time / 0.055) : 1 - Curve.easeOut((time - 0.055) / 0.095)
    }

    private func spring(_ start: Double, _ response: Double, _ damping: Double) -> Double {
        Curve.spring(elapsed - start, response: response, damping: damping)
    }

    private func ramp(_ start: Double, _ end: Double) -> Double {
        min(1, max(0, (elapsed - start) / (end - start)))
    }

    private func bump(_ start: Double, _ end: Double) -> Double {
        let progress = ramp(start, end)
        return progress > 0 && progress < 1 ? sin(.pi * progress) : 0
    }
}
