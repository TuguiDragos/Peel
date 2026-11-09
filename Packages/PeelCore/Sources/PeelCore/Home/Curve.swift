import Foundation

/// CSS's timing functions, since every curve the face moves along is written in them.
public enum Curve {
    public static func easeIn(_ x: Double) -> Double { solve(x, 0.42, 0, 1, 1) }
    public static func easeOut(_ x: Double) -> Double { solve(x, 0, 0, 0.58, 1) }
    public static func easeInOut(_ x: Double) -> Double { solve(x, 0.42, 0, 0.58, 1) }
    public static func morph(_ x: Double) -> Double { solve(x, 0.45, 0.05, 0.5, 1) }
    public static func lift(_ x: Double) -> Double { solve(x, 0.23, 1, 0.32, 1) }

    /// A spring let go `elapsed` seconds ago, from 0 toward 1: it takes about `response` seconds to swing there, and
    /// below a `damping` of 1 it goes a little past and settles back, as a spring does. 0 before it is let go.
    public static func spring(_ elapsed: Double, response: Double, damping: Double) -> Double {
        guard elapsed > 0 else { return 0 }
        let omega = 2 * Double.pi / response
        guard damping < 1 else { return 1 - exp(-omega * elapsed) * (1 + omega * elapsed) }
        let swing = omega * (1 - damping * damping).squareRoot()
        let decay = exp(-damping * omega * elapsed)
        return 1 - decay * (cos(swing * elapsed) + damping * omega / swing * sin(swing * elapsed))
    }

    /// Returns the curve's y at `x`. The curve's parameter for `x` is found by Newton's method, starting from `x`.
    private static func solve(_ x: Double, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> Double {
        let cx = 3 * x1, bx = 3 * (x2 - x1) - cx, ax = 1 - cx - bx
        let cy = 3 * y1, by = 3 * (y2 - y1) - cy, ay = 1 - cy - by
        var t = x
        for _ in 0..<8 {
            let error = ((ax * t + bx) * t + cx) * t - x
            if abs(error) < 1e-5 { break }
            let slope = (3 * ax * t + 2 * bx) * t + cx
            if abs(slope) < 1e-6 { break }
            t -= error / slope
        }
        return ((ay * t + by) * t + cy) * t
    }
}
