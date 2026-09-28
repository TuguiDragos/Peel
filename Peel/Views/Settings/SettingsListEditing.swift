import SwiftUI

/// Returns the height of a Settings list with `rows` entries, at 24 points a row: the list fits its entries, up to
/// eight rows, and scrolls beyond that.
func settingsListHeight(rows: Int) -> CGFloat {
    CGFloat(min(rows, 8)) * 24
}

extension View {
    /// Styles the buttons that add to a list and remove from it as small bordered buttons, 20 points high, the
    /// HIG's minimum on the Mac. A borderless pull-down stays 16 points high at every control size, so they all use
    /// this style.
    func editingControls() -> some View {
        buttonStyle(.bordered)
            .controlSize(.small)
    }
}
