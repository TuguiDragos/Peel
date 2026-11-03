public import CoreGraphics

/// Where the buttons of a page go: together at the right edge, the last, its main action, at the edge itself. When a
/// language's words leave no room on one line, the first ones take a line above, also at the right edge. Buttons that
/// lead, those that keep what the page is about, such as Start and Disable, stand at the left edge instead, on the
/// line of the others while there is room, and on the lines above them otherwise.
public struct ActionRowPlan: Equatable, Sendable {
    public let frames: [CGRect]
    public let size: CGSize

    /// - Parameters:
    ///   - sizes: Each button's own size. What has no width, a group with nothing to show, takes no room.
    ///   - leading: Which buttons lead, by their place in `sizes`.
    public init(
        sizes: [CGSize], width: CGFloat?, spacing: CGFloat = 8, lineSpacing: CGFloat = 6, leading: [Bool] = []
    ) {
        let shown = sizes.indices.filter { sizes[$0].width > 0 }
        let leads = shown.filter { leading.indices.contains($0) && leading[$0] }
        let follows = shown.filter { !leads.contains($0) }
        func needed(_ indices: [Int]) -> CGFloat {
            indices.reduce(0) { $0 + sizes[$1].width } + spacing * CGFloat(max(indices.count - 1, 0))
        }
        let room = width.flatMap { $0.isFinite ? $0 : nil } ?? needed(shown)

        let oneLine = !leads.isEmpty && !follows.isEmpty && needed(shown) <= room
        var lines = oneLine ? [] : Self.lines(of: leads, sizes, room: room, spacing: spacing, fromTheRight: false)
        let trailing = Self.lines(of: follows, sizes, room: room, spacing: spacing, fromTheRight: true)
        lines += oneLine ? [Line(leading: leads, trailing: follows)] : trailing

        var frames = [CGRect](repeating: .zero, count: sizes.count)
        var y: CGFloat = 0
        for line in lines {
            let height = (line.leading + line.trailing).reduce(0) { max($0, sizes[$1].height) }
            func place(_ index: Int, at x: CGFloat) {
                frames[index] = CGRect(
                    x: x, y: y + (height - sizes[index].height) / 2, width: min(sizes[index].width, room),
                    height: sizes[index].height
                )
            }
            var x: CGFloat = 0
            for index in line.leading {
                place(index, at: x)
                x += min(sizes[index].width, room) + spacing
            }
            x = room
            for index in line.trailing.reversed() {
                x -= min(sizes[index].width, room)
                place(index, at: x)
                x -= spacing
            }
            y += height + lineSpacing
        }
        self.frames = frames
        size = CGSize(width: room, height: lines.isEmpty ? 0 : y - lineSpacing)
    }

    private struct Line {
        var leading: [Int] = []
        var trailing: [Int] = []
    }

    /// The lines `indices` take, as many as fit on each: from the right edge, the first ones on the line above, or
    /// from the left edge, the last ones on the line below.
    private static func lines(
        of indices: [Int], _ sizes: [CGSize], room: CGFloat, spacing: CGFloat, fromTheRight: Bool
    ) -> [Line] {
        var lines: [[Int]] = []
        var used: CGFloat = 0
        for index in fromTheRight ? indices.reversed() : indices {
            let width = min(sizes[index].width, room)
            let line = fromTheRight ? lines.first : lines.last
            if let line, !line.isEmpty, used + spacing + width <= room {
                if fromTheRight { lines[0].insert(index, at: 0) } else { lines[lines.count - 1].append(index) }
                used += spacing + width
            } else {
                if fromTheRight { lines.insert([index], at: 0) } else { lines.append([index]) }
                used = width
            }
        }
        return lines.map { fromTheRight ? Line(trailing: $0) : Line(leading: $0) }
    }
}
