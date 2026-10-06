import SwiftUI

extension View {
    /// Keeps the title bar clear on macOS 27: no background behind each column's section of it, and, outside the
    /// sidebar's head, nothing drawn over what scrolls beneath it.
    @ViewBuilder
    func clearTitleBar() -> some View {
        if #available(macOS 27, *) {
            toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
                .scrollEdgeEffectHidden(true, for: .top)
        } else {
            self
        }
    }
}
