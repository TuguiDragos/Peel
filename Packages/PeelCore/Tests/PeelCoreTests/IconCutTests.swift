import Foundation
@testable import PeelCore
import Testing

struct IconCutTests {
    /// A box whose gray darkens toward the bottom, and on it Peel's sticker: an orange disc with a soft shadow below
    /// and to its right, or the disc's outline alone.
    private func icon(side: Int, outlineOnly: Bool = false) -> [UInt8] {
        let size = Double(side)
        let cx = IconCut.center.x * size, cy = IconCut.center.y * size, radius = IconCut.radius * size
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        for y in 0..<side {
            for x in 0..<side {
                let gray = 240 - 24 * Double(y) / size
                var color = [gray, gray, gray]
                let distance = hypot(Double(x) + 0.5 - cx, Double(y) + 0.5 - cy)
                let shadow = hypot(Double(x) + 0.5 - cx - 0.012 * size, Double(y) + 0.5 - cy - 0.02 * size)
                if outlineOnly {
                    if abs(distance - radius) < 0.6 { color = [255, 255, 255] }
                } else if distance < radius {
                    color = [240, 120, 30]
                } else if shadow < radius + 0.02 * size {
                    color = color.map { $0 * 0.86 }
                }
                let index = (y * side + x) * 4
                for channel in 0..<3 { pixels[index + channel] = UInt8(color[channel].rounded()) }
                pixels[index + 3] = 255
            }
        }
        return pixels
    }

    @Test(arguments: [96, 192]) func takesTheStickerAndItsShadowOffAndFillsItsPlaceWithTheBox(side: Int) {
        let pixels = icon(side: side)
        let cut = IconCut(pixels: pixels, side: side)
        #expect(cut.isWhole)
        var worst = 0
        for index in 0..<side * side {
            let opacity = Double(cut.sticker[index * 4 + 3]) / 255
            for channel in 0..<4 {
                let under = (1 - opacity) * Double(cut.box[index * 4 + channel])
                let back = Double(cut.sticker[index * 4 + channel]) + under
                worst = max(worst, abs(Int(back.rounded()) - Int(pixels[index * 4 + channel])))
            }
        }
        #expect(worst <= 4)
        let middle = Int(IconCut.center.y * Double(side)) * side + Int(IconCut.center.x * Double(side))
        let gray = 240 - 24 * Double(middle / side) / Double(side)
        #expect(abs(Double(cut.box[middle * 4]) - gray) < 3)
        #expect(cut.sticker[middle * 4 + 3] == 255)
        let above = Int((IconCut.center.y - 1.12 * IconCut.radius) * Double(side)) * side
            + Int(IconCut.center.x * Double(side))
        #expect(cut.sticker[above * 4 + 3] == 0)
    }

    @Test func leavesAStickerDrawnOnlyInOutlineOnItsBox() {
        #expect(!IconCut(pixels: icon(side: 192, outlineOnly: true), side: 192).isWhole)
    }
}
