public import CoreGraphics

/// Where a window that grew has to stand to stay on its screen.
public enum GrowingWindow {
    /// `frame` moved up just as far as its bottom needs to be within `visible`, and never so far that its top passes
    /// the top of `visible`. Both are in screen coordinates, which grow upward.
    public static func frame(_ frame: CGRect, within visible: CGRect) -> CGRect {
        let lowest = frame.height <= visible.height ? visible.minY : visible.maxY - frame.height
        guard frame.minY < lowest else { return frame }
        return CGRect(x: frame.minX, y: lowest, width: frame.width, height: frame.height)
    }
}
