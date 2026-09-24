import SwiftUI

extension View {
    /// Tints a mark in a list row with `color`, or with the secondary style when `color` is nil. A selected
    /// row's highlight can be the same color, so there the mark uses the primary style to stay visible.
    func rowTint(_ color: Color?) -> some View {
        modifier(RowTint(color: color))
    }
}

private struct RowTint: ViewModifier {
    @Environment(\.backgroundProminence) private var prominence
    let color: Color?

    func body(content: Content) -> some View {
        if let color, prominence != .increased {
            content.foregroundStyle(color)
        } else {
            content.foregroundStyle(color == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
        }
    }
}
