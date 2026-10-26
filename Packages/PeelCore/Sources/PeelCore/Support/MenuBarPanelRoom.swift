public import Foundation

/// How tall the menu bar panel may be. It opens under the menu bar of whichever display was clicked, and macOS
/// neither shortens nor scrolls a panel taller than its screen, so it fits the least room any display has, with a
/// little space kept below it.
public enum MenuBarPanelRoom {
    static let spaceBelow: CGFloat = 8

    public static func height(within visibleHeights: [CGFloat]) -> CGFloat? {
        visibleHeights.min().map { max($0 - spaceBelow, 0) }
    }
}
