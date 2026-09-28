import Foundation

/// Hitch counts for a stretch of the app's run: how long each turn of the main run loop kept the main thread
/// busy, and how many frames the display asked for that the app missed.
public struct Hitches: Sendable {
    private var turns = 0
    private var longestTurn = 0.0
    private var turnsOverAFrame = 0
    private var callbacks = 0
    private var shortestPeriod: Double?
    private var latestPeriod: Double?
    private var worstGap = 0.0
    private var missed = 0
    private var lastFrame: Double?

    public init() {}

    /// Records one turn of the main run loop that kept the main thread busy for `seconds`. Returns true when
    /// the turn took longer than a frame: the display's latest period, or a sixtieth of a second until the
    /// display reports one, the slowest rate a Mac display runs at.
    @discardableResult
    public mutating func turn(lasting seconds: Double) -> Bool {
        turns += 1
        longestTurn = max(longestTurn, seconds)
        guard seconds > (latestPeriod ?? 1.0 / 60) else { return false }
        turnsOverAFrame += 1
        return true
    }

    /// Records a frame the display asked for at `timestamp`, with the next one due at `target`. A gap is judged
    /// against the period of the frame that ends it, so a display that slows down when little moves is not
    /// counted as missing frames.
    public mutating func frame(at timestamp: Double, due target: Double) {
        let period = target - timestamp
        callbacks += 1
        if let lastFrame, period > 0 {
            let gap = timestamp - lastFrame
            worstGap = max(worstGap, gap)
            missed += max(0, Int((gap / period).rounded()) - 1)
        }
        lastFrame = timestamp
        latestPeriod = period
        shortestPeriod = min(shortestPeriod ?? period, period)
    }

    /// Marks a stretch the display asked for no frames, as for a window out of sight: the next frame starts afresh
    /// instead of counting the wait as frames missed.
    public mutating func pause() {
        lastFrame = nil
    }

    public var report: [String] {
        let runLoop = String(format: "run loop: %ld turns, longest %.1f ms, %ld over one frame",
                             turns, longestTurn * 1000, turnsOverAFrame)
        guard let shortestPeriod else { return [runLoop, "frames: 0 callbacks"] }
        return [runLoop, String(format: "frames: %ld callbacks, period %.2f ms, worst gap %.1f ms, %ld missed",
                                callbacks, shortestPeriod * 1000, worstGap * 1000, missed)]
    }
}
