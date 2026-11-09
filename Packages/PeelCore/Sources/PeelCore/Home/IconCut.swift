import Foundation

/// About's icon taken apart for the face's scene: the box, with the sticker's place filled in from the box's own colors
/// around it, and the sticker alone, carrying only what differs from the box under it (its disc, its curl and its
/// shadow), so the sticker can move while the box stays. Over the box, at rest, the two give back the icon. Pixels are
/// premultiplied RGBA, eight bits a channel, row by row from the top, in a square `side` pixels wide.
public struct IconCut: Sendable {
    /// Where the sticker sits on the icon, as fractions of its side: `Logo/Peel.icon` draws a circle of radius 330
    /// around (527.2, 496.8) on a canvas 1024 wide, which macOS draws in a tile 824 of 1024 wide in the middle.
    public static let center = (x: (100 + 527.2 * 824 / 1024) / 1024, y: (100 + 496.8 * 824 / 1024) / 1024)
    public static let radius = 330.0 * 824 / 1024 / 1024

    public let box: [UInt8]
    public let sticker: [UInt8]
    /// Whether the sticker comes away whole: most of its circle carried solid, and the two parts at rest within a few
    /// levels of the icon. A sticker drawn only in outline, as a Debug build's icon draws it, stays on its box.
    public let isWhole: Bool

    public init(pixels: [UInt8], side: Int) {
        let size = Double(side)
        let cx = Self.center.x * size, cy = Self.center.y * size, radius = Self.radius * size
        // A little more than the sticker, for the tip of its curl and the shadow it casts down and to the right.
        let reach = 1.2 * radius
        let edge = max(1, size / 96)
        let margin = max(2, side / 64)
        let left = min(max(1, Int(cx - reach) - margin), side - 2)
        let right = min(max(1, Int(cx + reach) + margin), side - 2)
        var values = pixels.map(Double.init)
        var weight = [Double](repeating: 0, count: side * side)
        var inside: [Int] = []
        for y in 1..<side - 1 {
            for x in 1..<side - 1 {
                let distance = hypot(Double(x) + 0.5 - cx, Double(y) + 0.5 - cy)
                weight[y * side + x] = min(1, max(0, (reach - distance) / edge))
                guard distance < reach + 1 else { continue }
                inside.append(y * side + x)
                // A first guess: the box's colors either side of the sticker on this row, blended across.
                let across = Double(x - left) / Double(right - left)
                for channel in 0..<4 {
                    var leftSum = 0.0, rightSum = 0.0
                    for offset in -1...1 {
                        leftSum += Double(pixels[(y * side + left + offset) * 4 + channel])
                        rightSum += Double(pixels[(y * side + right + offset) * 4 + channel])
                    }
                    values[(y * side + x) * 4 + channel] = leftSum / 3 * (1 - across) + rightSum / 3 * across
                }
            }
        }
        // Then smoothed until it meets the box all around: each pixel moves to the mean of its four neighbors, a
        // little past it so it settles in fewer passes (successive over-relaxation).
        values.withUnsafeMutableBufferPointer { values in
            for _ in 0..<80 {
                for index in inside {
                    for channel in 0..<4 {
                        let at = index * 4 + channel
                        let mean = (values[at - 4] + values[at + 4] + values[at - side * 4] + values[at + side * 4]) / 4
                        values[at] += 1.9 * (mean - values[at])
                    }
                }
            }
        }
        var box = pixels, sticker = [UInt8](repeating: 0, count: pixels.count)
        for index in 0..<side * side {
            let cover = weight[index]
            guard cover > 0 else { continue }
            var difference = 0.0
            for channel in 0..<3 {
                difference = max(difference, abs(Double(pixels[index * 4 + channel]) - values[index * 4 + channel]))
            }
            // What differs from the box by more than a few levels is the sticker's, wholly past fourteen.
            let alpha = cover * min(1, max(0, (difference - 4) / 10))
            for channel in 0..<4 {
                let original = Double(pixels[index * 4 + channel])
                let under = (original * (1 - cover) + values[index * 4 + channel] * cover).rounded()
                box[index * 4 + channel] = UInt8(max(0, min(255, under)))
                let carried = channel == 3 ? alpha * 255 : original - (1 - alpha) * under
                sticker[index * 4 + channel] = UInt8(max(0, min(255, carried.rounded())))
            }
        }
        var worst = 0.0, solid = 0, circle = 0
        for index in 0..<side * side {
            let opacity = Double(sticker[index * 4 + 3]) / 255
            for channel in 0..<4 {
                let back = Double(sticker[index * 4 + channel]) + (1 - opacity) * Double(box[index * 4 + channel])
                worst = max(worst, abs(back - Double(pixels[index * 4 + channel])))
            }
            let x = index % side, y = index / side
            guard hypot(Double(x) + 0.5 - cx, Double(y) + 0.5 - cy) < radius else { continue }
            circle += 1
            if sticker[index * 4 + 3] >= 230 { solid += 1 }
        }
        self.box = box
        self.sticker = sticker
        isWhole = circle > 0 && Double(solid) / Double(circle) >= 0.75 && worst <= 6
    }
}
