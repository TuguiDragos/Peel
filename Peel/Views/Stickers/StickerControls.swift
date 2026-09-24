import SwiftUI

/// A torn strip of tape, used for section headers.
struct TapeHeader: View {
    let title: Text
    var fill: Color = Album.orange
    var ink: Color = .white
    var angle: Double = 0

    var body: some View {
        title
            .font(.system(size: 10.5, weight: .heavy, design: .rounded))
            .tracking(1.4)
            .textCase(.uppercase)
            .foregroundStyle(ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
            .background(TornStrip().fill(fill))
            .shadow(color: .black.opacity(0.12), radius: 1, y: 1)
            .rotationEffect(.degrees(angle))
            .accessibilityAddTraits(.isHeader)
    }
}

nonisolated struct TornStrip: Shape {
    func path(in rect: CGRect) -> Path {
        let step: CGFloat = 3.5, depth: CGFloat = 2.5
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        var y = rect.minY
        var inward = true
        while y < rect.maxY {
            y = min(y + step, rect.maxY)
            path.addLine(to: CGPoint(x: rect.maxX - (inward ? depth : 0), y: y))
            inward.toggle()
        }
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        inward = true
        while y > rect.minY {
            y = max(y - step, rect.minY)
            path.addLine(to: CGPoint(x: rect.minX + (inward ? depth : 0), y: y))
            inward.toggle()
        }
        path.closeSubpath()
        return path
    }
}

struct StickerButtonStyle: ButtonStyle {
    var fill: Color
    var size: CGFloat
    /// The label's color: white on every sticker but the quiet one.
    var ink: Color = .white
    private let edge: CGFloat = 3

    func makeBody(configuration: Configuration) -> some View {
        StickerLabel(configuration: configuration, fill: fill, ink: ink, size: size, edge: edge)
    }

    private struct StickerLabel: View {
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        let configuration: Configuration
        let fill: Color
        let ink: Color
        let size: CGFloat
        let edge: CGFloat

        /// A title with less width than it needs wraps onto as many lines as it takes: `fixedSize` keeps the
        /// row's height from cutting a long translation short.
        var body: some View {
            configuration.label
                .font(.system(size: size, weight: .bold, design: .rounded))
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(isEnabled ? ink : ink.opacity(0.6))
                .padding(.horizontal, size + 1)
                .padding(.vertical, size * 0.5)
                .sticker(radius: 20, fill: isEnabled ? fill : fill.opacity(0.45), edge: edge)
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
                .motion(.touch, value: configuration.isPressed)
        }
    }
}

extension ButtonStyle where Self == StickerButtonStyle {
    static func sticker(fill: Color, size: CGFloat = 13) -> Self {
        StickerButtonStyle(fill: fill, size: size)
    }

    /// A quiet sticker, for actions that support the main one rather than compete with it.
    static var stickerQuiet: Self { StickerButtonStyle(fill: Album.quietFill, size: 12, ink: Album.ink) }
}

