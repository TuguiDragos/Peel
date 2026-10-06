public import Foundation

/// The smallest the main window may be, which gives every page the room it is laid out for. A screen with less
/// room than that, such as a 13 inch Mac set to Larger Text, gets a floor as big as the screen shows instead, so
/// the window never runs off it.
public enum WindowFloor {
    public static let preferred = CGSize(width: 1307, height: 756)

    public static func size(within visible: CGSize) -> CGSize {
        CGSize(width: min(preferred.width, visible.width), height: min(preferred.height, visible.height))
    }
}
