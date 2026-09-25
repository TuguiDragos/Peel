import SwiftUI

/// The style of a button in a List row: it looks like `.plain` but is no place keyboard focus could go, which a List
/// never sends to a row's button anyway. With a standard style, rows scrolling in and out change the window's places
/// for focus, which updates its toolbar and the app's scenes at every step of a scroll.
struct RowButtonStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PressableLabel(configuration: configuration)
    }
}

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
