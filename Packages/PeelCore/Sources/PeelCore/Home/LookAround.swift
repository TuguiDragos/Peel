import Foundation

/// Where the face at the top of the sidebar looks while the pointer is outside the window. For a second it keeps
/// looking where the pointer left, then it turns back to the user, and then it slowly looks every way in turn,
/// holding each look.
public struct LookAround: Sendable {
    /// Where the face looks at one moment. `aim` is a fraction of how far the face can look (x to the right,
    /// y down). `hold`, from 0 to 1, is how fully the face follows `aim`: at 0 it rests, looking at the user.
    public struct Moment: Equatable, Sendable {
        public var aim: SIMD2<Double>
        public var hold: Double

        public init(aim: SIMD2<Double>, hold: Double) {
            self.aim = aim
            self.hold = hold
        }

        static let rest = Moment(aim: .zero, hold: 0)
    }

    private struct Place {
        let moment: Moment
        let seconds: Double

        init(_ x: Double, _ y: Double, for seconds: Double) {
            moment = Moment(aim: [x, y], hold: 1)
            self.seconds = seconds
        }

        init(restingFor seconds: Double) {
            moment = .rest
            self.seconds = seconds
        }
    }

    private static let linger = 1.0

    /// One round: every direction once, with two rests. The holds vary so the motion has no steady rhythm.
    private static let places = [
        Place(restingFor: 1.6),
        Place(-0.8, -0.6, for: 1.8),
        Place(0.99, 0.1, for: 2.2),
        Place(-0.65, 0.75, for: 1.6),
        Place(restingFor: 2),
        Place(0.1, -0.99, for: 2),
        Place(0.55, -0.45, for: 1.4),
        Place(-0.99, -0.05, for: 2.4),
        Place(0.7, 0.7, for: 1.6),
        Place(-0.1, 0.6, for: 1.4),
    ]

    private static let cycle = places.indices.reduce(0) { total, index in
        total + places[index].seconds + travel(from: places[index].moment, to: places[(index + 1) % places.count].moment)
    }

    private let start: Moment

    public init(from start: Moment) {
        self.start = start
    }

    public func moment(after elapsed: Double) -> Moment {
        var time = elapsed - Self.linger
        guard time > 0 else { return start }
        let first = Self.places[0].moment
        let arriving = Self.travel(from: start, to: first)
        guard time >= arriving else { return Self.blend(start, first, time / arriving) }
        time = (time - arriving).truncatingRemainder(dividingBy: Self.cycle)
        for index in Self.places.indices {
            let place = Self.places[index]
            let next = Self.places[(index + 1) % Self.places.count].moment
            guard time >= place.seconds else { return place.moment }
            time -= place.seconds
            let travel = Self.travel(from: place.moment, to: next)
            guard time >= travel else { return Self.blend(place.moment, next, time / travel) }
            time -= travel
        }
        return first
    }

    /// How long a turn takes: 0.8 s plus 0.4 s per unit of distance between the aims, so 1.6 s from one side
    /// to the other. A longer turn takes longer, as it does for a real head.
    private static func travel(from: Moment, to: Moment) -> Double {
        let way = to.aim - from.aim
        return 0.8 + 0.4 * (way * way).sum().squareRoot()
    }

    /// Blends two moments. The aim eases in and out. The hold changes evenly, because the face already eases
    /// the hold it is given.
    private static func blend(_ from: Moment, _ to: Moment, _ progress: Double) -> Moment {
        let eased = (1 - cos(.pi * progress)) / 2
        return Moment(aim: from.aim + (to.aim - from.aim) * eased, hold: from.hold + (to.hold - from.hold) * progress)
    }
}
