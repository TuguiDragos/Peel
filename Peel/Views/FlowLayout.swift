import SwiftUI

/// Lays its views out in a line and starts another line when the next one would not fit, as text wraps its
/// words. For the badges and buttons under a title: in one `HStack`, a translated badge would break in two
/// inside its capsule and a button's title would be cut.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(subviews, in: proposal.width ?? .infinity).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let arrangement = arrange(subviews, in: bounds.width)
        for (subview, frame) in zip(subviews, arrangement.frames) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), proposal: ProposedViewSize(frame.size))
        }
    }

    /// Each view at its own width, or the whole width when it is wider than that, and each line's views centered
    /// on the line.
    private func arrange(_ subviews: Subviews, in width: CGFloat) -> (frames: [CGRect], size: CGSize) {
        var frames: [CGRect] = []
        var lineStart = 0
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, widest: CGFloat = 0

        func closeLine() {
            for index in lineStart..<frames.count {
                frames[index].origin.y = y + (lineHeight - frames[index].height) / 2
            }
            lineStart = frames.count
        }

        for subview in subviews {
            var size = subview.sizeThatFits(.unspecified)
            if size.width > width {
                size = subview.sizeThatFits(ProposedViewSize(width: width, height: nil))
            }
            if x > 0, x + size.width > width {
                closeLine()
                y += lineHeight + lineSpacing
                x = 0
                lineHeight = 0
            }
            frames.append(CGRect(x: x, y: y, width: size.width, height: size.height))
            widest = max(widest, x + size.width)
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        closeLine()
        return (frames, CGSize(width: widest, height: frames.isEmpty ? 0 : y + lineHeight))
    }
}
