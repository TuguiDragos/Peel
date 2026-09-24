/// Decides whether a drawing has moved enough since the last frame sent to be worth another. Each frame costs
/// WindowServer about the same however little moved, and the breathing of Peel's face moves it only about a
/// hundredth of a pixel per frame. So a frame goes out only once some point has moved a tenth of a pixel.
public struct VisibleMotion: Sendable {
    static let threshold = 0.1
    private var sent: [SIMD2<Double>]?

    public init() {}

    /// Returns whether `points` moved enough to be worth a frame, and remembers them if so. `points` are the same
    /// spots on the drawing every frame, in points, and `pixelsPerPoint` is the display's scale.
    @discardableResult
    public mutating func isWorthAFrame(_ points: [SIMD2<Double>], pixelsPerPoint: Double) -> Bool {
        let reach = Self.threshold / pixelsPerPoint
        if let sent, sent.count == points.count,
           zip(sent, points).allSatisfy({ (($1 - $0) * ($1 - $0)).sum() < reach * reach }) {
            return false
        }
        sent = points
        return true
    }
}
