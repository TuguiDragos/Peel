/// The smile the face at the top of the sidebar gives once when a removal finishes. It asks for the face's happy
/// pose for as long as the pose takes to arrive and one beat more, then lets it go, and it is over once the pose
/// has had time to leave. Time is counted in the steps the face takes, never read from the clock, so a face that
/// rested while Peel was in the background goes on from where it stopped.
public struct Cheer: Sendable {
    private let rise: Double
    private let hold: Double
    private let fall: Double
    private var elapsed: Double = 0

    /// `rise` and `fall` are how long the face's smile takes to arrive and to leave, `hold` how long it stays.
    public init(rise: Double, hold: Double, fall: Double) {
        self.rise = rise
        self.hold = hold
        self.fall = fall
    }

    public mutating func advance(by step: Double) {
        elapsed += max(0, step)
    }

    public var wantsHappyPose: Bool {
        elapsed < rise + hold
    }

    public var isOver: Bool {
        elapsed >= rise + hold + fall
    }
}
