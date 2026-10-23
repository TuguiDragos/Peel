import AppKit
@testable import Peel
import SwiftUI
import Testing
import UniformTypeIdentifiers

struct DieCutTests {
    @Test(arguments: ["Mac13,1", "Mac14,2", "VirtualMac"], [2.0, 1.0])
    func theContourIsAsWideAllAroundThePictureAndNoWider(model: String, scale: Double) throws {
        let kind = try #require(
            UTType(tag: model, tagClass: UTTagClass(rawValue: "com.apple.device-model-code"), conformingTo: nil)
        )
        let picture = NSWorkspace.shared.icon(for: kind)

        let sticker = try solidPart(of: DieCut(image: picture), scale: scale)
        let alone = try solidPart(of: Image(nsImage: picture).resizable().aspectRatio(contentMode: .fit), scale: scale)
        let reach = [
            alone.minY - sticker.minY, sticker.maxY - alone.maxY, alone.minX - sticker.minX, sticker.maxX - alone.maxX,
        ]

        #expect(reach.allSatisfy { (3.5...5.5).contains($0) }, "\(reach)")
    }

    private func solidPart(of view: some View, scale: Double) throws -> CGRect {
        let renderer = ImageRenderer(
            content: view.frame(width: 104, height: 104).padding(8).environment(\.colorScheme, .light)
        )
        renderer.scale = scale
        let image = try #require(renderer.cgImage)
        let context = try #require(CGContext(
            data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let pixels = try #require(context.data).bindMemory(to: UInt8.self, capacity: image.width * image.height * 4)
        var solid = CGRect.null
        for y in 0..<image.height {
            for x in 0..<image.width where pixels[(y * image.width + x) * 4 + 3] >= 128 {
                let pixel = CGRect(x: Double(x) / scale, y: Double(y) / scale, width: 1 / scale, height: 1 / scale)
                solid = solid.union(pixel)
            }
        }
        return solid
    }
}
