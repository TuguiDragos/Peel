import AppKit
import PeelCore
import SwiftUI
import UniformTypeIdentifiers

struct DeviceSticker: View {
    let value: String
    /// The number that `value` shows, so the digits roll in the direction the number changed.
    var amount: Double?
    let label: LocalizedStringResource
    let fill: Color
    let ink: Color
    let width: CGFloat
    let radius: CGFloat
    let angle: Double
    /// The width of the label's longest word. A sticker narrower than this would break the word in two.
    @State private var longestWord: CGFloat = 0
    /// The width of `value` at its full size, such as "Over 12.3 GB", which a narrower sticker would shrink or cut.
    @State private var valueWidth: CGFloat = 0
    /// How far the label's last line sits above the sticker's bottom edge.
    @State private var labelRise: CGFloat = .infinity

    private static let labelFont = Font.system(.caption, design: .rounded, weight: .semibold)
    private static let valueFont = Font.system(size: 16, weight: .bold, design: .rounded)

    /// At least 62 points tall, and taller when the words need it. In a row, every sticker stretches to the
    /// height of the tallest one. As wide as `width`, or wider when the words or the figure need it.
    var body: some View {
        VStack(spacing: 0) {
            Text(value)
                .font(Self.valueFont)
                .monospacedDigit()
                .contentTransition(.numericText(value: amount ?? 0))
                .motion(value: value)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .padding(.horizontal, 5)
                .background {
                    Text(value)
                        .font(Self.valueFont)
                        .monospacedDigit()
                        .fixedSize()
                        .hidden()
                        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { valueWidth = $0 }
                }
            Text(label)
                .font(Self.labelFont)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { proxy in
                    (proxy.bounds(of: .named(Self.space))?.height ?? 0) - proxy.frame(in: .named(Self.space)).maxY
                } action: { labelRise = $0 }
                .padding(.horizontal, 5 + curveRoom / 2)
                .opacity(0.7)
                .background { LongestWord(text: String(localized: label), width: $longestWord).font(Self.labelFont) }
        }
        .foregroundStyle(ink)
        .padding(.vertical, 6)
        .frame(width: wordsWidth + curveRoom)
        .frame(minHeight: 62, maxHeight: .infinity)
        .coordinateSpace(.named(Self.space))
        .sticker(radius: radius, fill: fill, edge: 3)
        .rotationEffect(.degrees(angle))
        .accessibilityElement(children: .combine)
    }

    private nonisolated static let space = "sticker"

    /// The width before `curveRoom`: `width`, or the longest word or the figure with 5 points on each side if
    /// that is wider.
    private var wordsWidth: CGFloat {
        max(width, ceil(longestWord) + 10, ceil(valueWidth) + 10)
    }

    /// Extra width that keeps the clipping curve of a round sticker 3 points clear of the longest word on the
    /// label's last line. The sticker and the label's margins widen alike, so the words break into the same lines.
    private var curveRoom: CGFloat {
        guard labelRise < radius else { return 0 }
        let intrusion = radius - (radius * radius - (radius - labelRise) * (radius - labelRise)).squareRoot()
        return max(0, ceil(ceil(longestWord) + 6 + 2 * intrusion - wordsWidth))
    }
}

/// Shows how much of the disk is used, as a bar inside a slot that stands for the whole disk. On Home
/// (`isAlbum`), the bar is a strip of tape in a die-cut slot. Elsewhere it is plain, since `Album.*` and a
/// rounded font belong only to Home, the menu bar panel, and About.
struct StorageStrip: View {
    let storage: DeviceInfo.Storage
    var isAlbum = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(storage.free.byteCount) available")
                    .font(isAlbum ? .system(size: 15, weight: .bold, design: .rounded) : .title3.weight(.semibold))
                    .foregroundStyle(isAlbum ? AnyShapeStyle(Album.ink) : AnyShapeStyle(.primary))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(storage.free)))
                Spacer(minLength: 8)
                Text("of \(storage.total.byteCount)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            GeometryReader { proxy in
                let room = max(0, proxy.size.width - 8)
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isAlbum ? AnyShapeStyle(Album.slot) : AnyShapeStyle(.quaternary))
                    if isAlbum {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.28), style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
                    }
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isAlbum ? Album.orange : Color.accentColor)
                        .frame(width: min(room, max(16, room * storage.usedFraction)), height: 16)
                        .shadow(color: isAlbum ? Album.shadow : .clear, radius: 1, y: 1)
                        .padding(.leading, 4)
                        .motion(.settle, .movement, value: storage.used)
                }
            }
            .frame(height: 24)
            Text("\(storage.used.byteCount) used")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(storage.used)))
        }
        .motion(value: storage)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Storage: \(storage.free.byteCount) available of \(storage.total.byteCount)"))
    }
}

extension DeviceInfo {
    /// The picture macOS keeps for `modelIdentifier`, which follows the light or dark appearance by itself.
    /// For a model macOS doesn't know, `UTType` returns a dynamic type (`UTType.h`) whose icon is a generic
    /// document, so the plain computer picture is used instead.
    var image: NSImage? {
        if let image = DeviceImages.byModel[modelIdentifier] { return image }
        guard
            let type = UTType(tag: modelIdentifier, tagClass: UTTagClass(rawValue: "com.apple.device-model-code"), conformingTo: nil),
            !type.isDynamic
        else { return NSImage(named: NSImage.computerName) }
        let image = NSWorkspace.shared.icon(for: type)
        DeviceImages.byModel[modelIdentifier] = image
        return image
    }

    /// The chip's name, short enough for a sticker: "M3 Pro" rather than "Apple M3 Pro", and for an Intel Mac
    /// the processor family, "Intel Core i9" rather than "Intel(R) Core(TM) i9-9980HK CPU @ 2.40GHz".
    var chipName: String {
        guard !chip.hasPrefix("Apple ") else { return String(chip.dropFirst("Apple ".count)) }
        var name = chip.replacingOccurrences(of: "(R)", with: "").replacingOccurrences(of: "(TM)", with: "")
        if let at = name.firstIndex(of: "@") { name = String(name[..<at]) }
        name = name.replacingOccurrences(of: " CPU", with: "")
        if let dash = name.firstIndex(of: "-") { name = String(name[..<dash]) }
        return name.split(separator: " ").joined(separator: " ")
    }
}

/// A cache of device pictures by model identifier. The card is drawn again on every activation, and a Mac's
/// model never changes.
private enum DeviceImages {
    static var byModel: [String: NSImage] = [:]
}
