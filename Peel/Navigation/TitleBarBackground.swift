import SwiftUI

extension View {
    /// Keeps the title bar clear. Otherwise the window draws a background behind each column's section of the title
    /// bar even when nothing is under it: always on macOS 27, and on macOS 26 while the sidebar is hidden, an opaque
    /// band with a line under it. What scrolls beneath the title bar is still blurred by the scroll edge effect.
    func clearTitleBar() -> some View {
        toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
    }
}
