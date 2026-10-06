import SwiftUI

extension View {
    /// Keeps the title bar clear on macOS 27, as it is on macOS 26. There the window draws a background behind each
    /// column's section of the title bar even when nothing is under it; without it, what scrolls beneath the title
    /// bar is still blurred by the scroll edge effect.
    @ViewBuilder
    func clearTitleBar() -> some View {
        if #available(macOS 27, *) {
            toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        } else {
            self
        }
    }
}
