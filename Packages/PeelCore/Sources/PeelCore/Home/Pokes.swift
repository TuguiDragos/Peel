public import Foundation

/// Clicks on the icon in About: each one squashes it, and the fifth in a row wakes the face too, after which the count
/// starts again. A click more than `pause` after the one before starts it again too.
public struct Pokes: Sendable {
    public enum Answer: Sendable, Equatable {
        /// The `count`th click in a row, before the fifth wakes the face.
        case squash(count: Int)
        case wake
    }

    public static let pause: TimeInterval = 1.5
    public static let toWake = 5

    private var count = 0
    private var last: Date?

    public init() {}

    public mutating func poke(at date: Date) -> Answer {
        if let last, date.timeIntervalSince(last) > Self.pause { count = 0 }
        last = date
        count += 1
        guard count == Self.toWake else { return .squash(count: count) }
        count = 0
        return .wake
    }
}
