import AppKit
@testable import Peel
import SwiftUI
import Testing
import UniformTypeIdentifiers

struct DieCutTests {
    @Test(arguments: ["Mac13,1", "Mac14,2", "VirtualMac"], [2.0, 1.0])
    func theContourIsAsWideAllAroundThePictureAndNoWider(model: String, scale: Double) throws {
        let picture = try self.picture(of: model)

        let sticker = try solidPart(of: try rendered(DieCut(image: picture), padding: 8, scale: scale), scale: scale)
        let alone = try solidPart(of: try drawnByAppKit(picture, side: 120 * scale, inset: 8 * scale), scale: scale)
        let reach = [
            alone.minY - sticker.minY, sticker.maxY - alone.maxY, alone.minX - sticker.minX, sticker.maxX - alone.maxX,
        ]

        #expect(reach.allSatisfy { (3.5...5.5).contains($0) }, "\(reach)")
    }

    @Test(arguments: ["Mac15,12", "Mac13,1", "VirtualMac"], [2.0, 1.0])
    func thePictureIsAsSharpAsAppKitDrawsIt(model: String, scale: Double) throws {
        let picture = try self.picture(of: model)
        let side = Int(104 * scale)

        let shape = try pixels(of: try drawnByAppKit(picture, side: 104 * scale, inset: 0))
        let drawn = detail(of: try pixels(of: try rendered(DieCut(image: picture), padding: 0, scale: scale)),
                           inside: shape, side: side)
        let drawnByAppKit = detail(of: shape, inside: shape, side: side)

        #expect(drawn >= drawnByAppKit / 2, "\(drawn) of \(drawnByAppKit)")
    }

    private func picture(of model: String) throws -> NSImage {
        let kind = try #require(
            UTType(tag: model, tagClass: UTTagClass(rawValue: "com.apple.device-model-code"), conformingTo: nil)
        )
        return NSWorkspace.shared.icon(for: kind)
    }

    private func rendered(_ view: some View, padding: CGFloat, scale: Double) throws -> CGImage {
        let renderer = ImageRenderer(
            content: view.frame(width: 104, height: 104).padding(padding).environment(\.colorScheme, .light)
        )
        renderer.scale = scale
        return try #require(renderer.cgImage)
    }

    private func drawnByAppKit(_ picture: NSImage, side: Double, inset: Double) throws -> CGImage {
        let pixels = Int(side)
        let bitmap = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: pixels * 4, bitsPerPixel: 32
        ))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        picture.draw(in: NSRect(x: inset, y: inset, width: side - 2 * inset, height: side - 2 * inset))
        NSGraphicsContext.restoreGraphicsState()
        return try #require(bitmap.cgImage)
    }

    /// The energy of the luminance's Laplacian where `shape` is opaque all around a pixel, so inside the picture and
    /// never on the sticker's edge.
    private func detail(of image: [UInt8], inside shape: [UInt8], side: Int) -> Double {
        func isOpaque(_ x: Int, _ y: Int) -> Bool { shape[(y * side + x) * 4 + 3] >= 250 }
        func isInside(_ x: Int, _ y: Int) -> Bool {
            isOpaque(x, y) && isOpaque(x - 1, y) && isOpaque(x + 1, y) && isOpaque(x, y - 1) && isOpaque(x, y + 1)
        }
        func luminance(_ x: Int, _ y: Int) -> Double {
            let pixel = (y * side + x) * 4
            return 0.299 * Double(image[pixel]) + 0.587 * Double(image[pixel + 1]) + 0.114 * Double(image[pixel + 2])
        }
        var energy = 0.0, count = 0
        for y in 1..<(side - 1) {
            for x in 1..<(side - 1) where isInside(x, y) {
                let laplacian = 4 * luminance(x, y) - luminance(x - 1, y) - luminance(x + 1, y)
                    - luminance(x, y - 1) - luminance(x, y + 1)
                energy += laplacian * laplacian
                count += 1
            }
        }
        return count > 0 ? energy / Double(count) : 0
    }

    private func solidPart(of image: CGImage, scale: Double) throws -> CGRect {
        let pixels = try pixels(of: image)
        var solid = CGRect.null
        for y in 0..<image.height {
            for x in 0..<image.width where pixels[(y * image.width + x) * 4 + 3] >= 128 {
                let pixel = CGRect(x: Double(x) / scale, y: Double(y) / scale, width: 1 / scale, height: 1 / scale)
                solid = solid.union(pixel)
            }
        }
        return solid
    }

    private func pixels(of image: CGImage) throws -> [UInt8] {
        let context = try #require(CGContext(
            data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let count = image.width * image.height * 4
        let buffer = try #require(context.data).bindMemory(to: UInt8.self, capacity: count)
        return Array(UnsafeBufferPointer(start: buffer, count: count))
    }
}
