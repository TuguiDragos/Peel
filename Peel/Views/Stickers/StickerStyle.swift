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
    static let shadow = Color(.stickerShadow)
    static let quietFill = Color(.quietFill)
    /// The red of words and marks for what is missing, readable on a sticker in every appearance, which the system
    /// red is not. A red sticker under white ink takes `redFill`: in dark, no one red serves both.
    static let red = Color(.peelRed)
    static let redFill = Color(.peelRedFill)
    /// Orange for words and marks on the paper, where the brand orange is too light to read. The logo keeps `orange`.
    static let orangeInk = Color(.peelOrangeInk)
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
        ZStack {
            if showsBorders {
                contour(at: edge + 1, in: .primary)
            }
            contour(at: edge, in: Album.stickerEdge)
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
        }
        .compositingGroup()
        .shadow(color: Album.shadow, radius: 2.5, y: 1.5)
        .accessibilityIgnoresInvertColors()
    }

    /// An outline `distance` points wide around the image's shape: the shape drawn 20 times in one color, each
    /// copy moved `distance` points in a different direction.
    private func contour(at distance: CGFloat, in style: some ShapeStyle) -> some View {
        ForEach(0..<20, id: \.self) { step in
            let angle = Double(step) / 20 * 2 * .pi
            Image(nsImage: image)
                .resizable()
                .renderingMode(.template)
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(style)
                .offset(x: cos(angle) * distance, y: sin(angle) * distance)
        }
    }
}

/// A dashed hairline, like the cut lines on a sheet of stickers.
struct Perforation: View {
    var body: some View {
        Line()
            .stroke(Color.primary.opacity(0.13), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
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
