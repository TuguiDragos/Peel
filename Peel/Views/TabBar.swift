import AppKit

enum TabBar {
    /// The width a page's tabs need in the title bar. On macOS 26 the toolbar draws them as one segmented control
    /// with equal segments: the widest title plus 23.5 points, or plus 27 at either end. The toolbar shows the
    /// control only while the column is 24 points wider than it, and otherwise moves it into the overflow menu.
    /// `ContentView` moves the sidebar aside when the window is too narrow for both.
    static func width(of titles: [String]) -> CGFloat {
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let widest = titles.indices.map { index in
            let end = index == 0 || index == titles.count - 1
            return ceil((titles[index] as NSString).size(withAttributes: [.font: font]).width + (end ? 27 : 23.5))
        }.max() ?? 0
        return CGFloat(titles.count) * widest + 24
    }
}
