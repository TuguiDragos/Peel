import SwiftUI

/// The style of a button in a List row. It looks like `.plain`, which draws the label at three quarters while it is
/// pressed and at half while it is disabled, and it tracks the press with a gesture of its own.
///
/// A List takes keyboard focus as a whole, so a button in one of its rows is only ever pressed with the pointer or
/// through accessibility. A standard style still makes each such button a place keyboard focus could go, and the
/// window's list of those changes as rows scroll in and out, which updates the window's focus, its toolbar and the
/// app's scenes at every step of a scroll. A button with this style costs none of that.
struct RowButtonStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PressableLabel(configuration: configuration)
    }
}

/// Pressed while the pointer is down inside the label, and pressed for real only when it comes up there, as a
/// button is.
private struct PressableLabel: View {
    let configuration: RowButtonStyle.Configuration
    @Environment(\.isEnabled) private var isEnabled
    @State private var isPressed = false
    @State private var bounds = CGRect.zero

    var body: some View {
        configuration.label
            .opacity(isEnabled ? (isPressed ? 0.75 : 1) : 0.5)
            .onGeometryChange(for: CGRect.self) { CGRect(origin: .zero, size: $0.size) } action: { bounds = $0 }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        isPressed = isEnabled && bounds.contains(drag.location)
                    }
                    .onEnded { drag in
                        isPressed = false
                        if isEnabled, bounds.contains(drag.location) {
                            configuration.trigger()
                        }
                    }
            )
    }
}
