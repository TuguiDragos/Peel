public import CoreGraphics

/// Where the buttons of a page go: together at the right edge, the last, its main action, at the edge itself. When a
/// language's words leave no room on one line, the first ones take a line above, also at the right edge.
public struct ActionRowPlan: Equatable, Sendable {
    public let frames: [CGRect]
    public let size: CGSize

    /// - Parameter sizes: Each button's own size. What has no width, a group with nothing to show, takes no room.
    public init(sizes: [CGSize], width: CGFloat?, spacing: CGFloat = 8, lineSpacing: CGFloat = 6) {
        let shown = sizes.indices.filter { sizes[$0].width > 0 }
        let needed = shown.reduce(0) { $0 + sizes[$1].width } + spacing * CGFloat(max(shown.count - 1, 0))
        let room = width.flatMap { $0.isFinite ? $0 : nil } ?? needed

        var lines: [[Int]] = []
        var used: CGFloat = 0
        for index in shown.reversed() {
            let width = min(sizes[index].width, room)
            if let line = lines.first, !line.isEmpty, used + spacing + width <= room {
                lines[0].insert(index, at: 0)
                used += spacing + width
            } else {
                lines.insert([index], at: 0)
                used = width
            }
        }

        var frames = [CGRect](repeating: .zero, count: sizes.count)
        var y: CGFloat = 0
        for line in lines {
            let height = line.reduce(0) { max($0, sizes[$1].height) }
            var x = room
            for index in line.reversed() {
                let width = min(sizes[index].width, room)
                x -= width
                frames[index] = CGRect(
                    x: x, y: y + (height - sizes[index].height) / 2, width: width, height: sizes[index].height
                )
                x -= spacing
            }
            y += height + lineSpacing
        }
        self.frames = frames
        size = CGSize(width: room, height: lines.isEmpty ? 0 : y - lineSpacing)
    }
}
