import AppKit
import SwiftUI

/// The colors of the album look, which belongs to Home, the menu bar panel, and About: paper, stickers with a
/// die-cut edge, and Peel's orange. They live in `Peel/Assets.xcassets`, so they follow the appearance on their own.
enum Album {
    static let orange = Color(.peelOrange)
    static let cream = Color(.peelCream)
    static let charcoal = Color(.charcoal)
    /// The paper the stickers sit on. It is opaque, so it goes only under a surface of its own (the About window,
    /// the menu bar panel, a note). Under a column of the main window, it would leave the Liquid Glass of the
    /// toolbar and sidebar only a flat color to blur.
    static let sheet = Color(.sheet)
    static let stickerBody = Color(.stickerBody)
    static let stickerEdge = Color(.stickerEdge)
    static let ink = Color(.ink)
    static let slot = Color(.slot)
    /// The dashed edge of a slot, such as the storage bar's track. Increase Contrast darkens it to 3:1, as it does
    /// `cutLine`, the dashed line between a sheet's rows.
    static let slotEdge = Color(.slotEdge)
    static let cutLine = Color(.cutLine)
    static let shadow = Color(.stickerShadow)
    static let quietFill = Color(.quietFill)
    /// The red of words and marks for what is missing, readable on a sticker in every appearance, which the system
    /// red is not. A red sticker under white ink takes `redFill`: in dark, no one red serves both.
    static let red = Color(.peelRed)
    static let redFill = Color(.peelRedFill)
    /// Orange for words and marks on the paper, where the brand orange is too light to read. The logo keeps `orange`.
    static let orangeInk = Color(.peelOrangeInk)
    /// Orange for a mark on a `cream` sticker. The cream is the same in every appearance, so this orange is too,
    /// where `orangeInk` lightens in dark for the dark paper.
    static let orangeOnCream = Color(.peelOrangeOnCream)
    /// Words and marks drawn on `orange`: dark, and white where Increase Contrast darkens the orange.
    static let onOrange = Color(.inkOnOrange)
}

/// Draws content as a sticker: a body, a die-cut edge, and a short shadow. In the light appearance the white edge
/// barely stands out from what is behind it, and the catalog's high-contrast colors do not follow Show Borders,
/// which is its own setting from macOS 27. So under Show Borders the edge also gets a 1-point outline.
struct StickerBackground: ViewModifier {
    @Environment(\.accessibilityShowBorders) private var showsBorders
    var radius: CGFloat = 12
    var fill: Color = Album.stickerBody
    var edge: CGFloat = 4

    func body(content: Content) -> some View {
        content
            .background(fill, in: .rect(cornerRadius: radius, style: .continuous))
            .clipShape(.rect(cornerRadius: radius, style: .continuous))
            .padding(edge)
            .background(Album.stickerEdge, in: .rect(cornerRadius: radius + edge, style: .continuous))
            .overlay {
                if showsBorders {
                    RoundedRectangle(cornerRadius: radius + edge, style: .continuous)
                        .strokeBorder(.primary, lineWidth: 1)
                }
            }
            .compositingGroup()
            .shadow(color: Album.shadow, radius: 2.5, y: 1.5)
    }
}

extension View {
    func sticker(radius: CGFloat = 12, fill: Color = Album.stickerBody, edge: CGFloat = 4) -> some View {
        modifier(StickerBackground(radius: radius, fill: fill, edge: edge))
    }
}

/// An image cut out like a sticker: a light contour around its shape and a short shadow. Under Show Borders, a
/// 1-point outline goes around the contour, for the reason `StickerBackground` gives.
struct DieCut: View {
    @Environment(\.accessibilityShowBorders) private var showsBorders
    let image: NSImage
    var edge: CGFloat = 4

    var body: some View {
        Canvas { context, size in
            // One resolved image for contour and picture: SwiftUI picks an icon's rep by scale, and reps differ.
            let picture = context.resolve(Image(nsImage: image))
            let scale = min(size.width / picture.size.width, size.height / picture.size.height)
            let fitted = CGSize(width: picture.size.width * scale, height: picture.size.height * scale)
            let frame = CGRect(
                origin: CGPoint(x: (size.width - fitted.width) / 2, y: (size.height - fitted.height) / 2),
                size: fitted
            )
            if showsBorders {
                contour(of: picture, in: frame, at: edge + 1, color: .primary, on: context)
            }
            contour(of: picture, in: frame, at: edge, color: Album.stickerEdge, on: context)
            // Drawn only over the contour, so a shadow in the picture ends where the sticker does.
            context.blendMode = .sourceAtop
            context.draw(picture, in: frame)
        }
        .shadow(color: Album.shadow, radius: 2.5, y: 1.5)
        .accessibilityIgnoresInvertColors()
    }

    /// An outline `distance` points wide around what is at least half opaque in the picture, so not its soft shadow:
    /// that part drawn 20 times in one color, each copy moved another way, and once in place, under every thin part.
    private func contour(
        of picture: GraphicsContext.ResolvedImage, in frame: CGRect, at distance: CGFloat, color: Color,
        on context: GraphicsContext
    ) {
        var context = context
        context.addFilter(.alphaThreshold(min: 0.5, color: color))
        for step in 0...20 {
            let angle = Double(step) / 20 * 2 * .pi
            let moved = step < 20 ? distance : 0
            context.draw(picture, in: frame.offsetBy(dx: cos(angle) * moved, dy: sin(angle) * moved))
        }
    }
}

/// A dashed hairline, like the cut lines on a sheet of stickers.
struct Perforation: View {
    var body: some View {
        Line()
            .stroke(Album.cutLine, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            .frame(height: 1)
    }

    nonisolated private struct Line: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            return path
        }
    }
}
