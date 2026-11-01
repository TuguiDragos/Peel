public import CoreGraphics

/// Where the buttons at the foot of a page go. One is centered, and two stand at the ends of the row, unless they are
/// kept together in the middle. When a language's words leave no room on one line, each is centered on a line of its
/// own, so no title is cut.
public struct ActionRowPlan: Equatable, Sendable {
    public let frames: [CGRect]
    public let size: CGSize

    /// - Parameter sizes: Each button's own size. What has no width, a group with nothing to show, takes no room.
    public init(sizes: [CGSize], width: CGFloat?, keepsTogether: Bool = false, spacing: CGFloat = 8) {
        let shown = sizes.indices.filter { sizes[$0].width > 0 }
        let needed = shown.reduce(0) { $0 + sizes[$1].width } + spacing * CGFloat(max(shown.count - 1, 0))
        let room = width.flatMap { $0.isFinite ? $0 : nil } ?? needed
        var frames = [CGRect](repeating: .zero, count: sizes.count)
        var height: CGFloat = 0

        if needed <= room {
            height = shown.reduce(0) { max($0, sizes[$1].height) }
            let atTheEnds = shown.count == 2 && !keepsTogether
            var x = (room - needed) / 2
            for index in shown {
                let size = sizes[index]
                if atTheEnds { x = index == shown[0] ? 0 : room - size.width }
                frames[index] = CGRect(origin: CGPoint(x: x, y: (height - size.height) / 2), size: size)
                x += size.width + spacing
            }
        } else {
            for index in shown {
                let width = min(sizes[index].width, room)
                frames[index] = CGRect(x: (room - width) / 2, y: height, width: width, height: sizes[index].height)
                height += sizes[index].height + spacing
            }
            height -= spacing
        }
        self.frames = frames
        size = CGSize(width: room, height: height)
    }
}
