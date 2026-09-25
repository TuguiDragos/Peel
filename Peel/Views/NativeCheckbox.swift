import AppKit
import SwiftUI

/// A checkbox for a list's rows: AppKit's own button, at the size AppKit gives it.
///
/// SwiftUI's checkbox `Toggle` is the same button, but SwiftUI asks the button for its size every time the list
/// measures a row, and a list measures each row as it scrolls into view, so a list of them drops frames while it
/// scrolls. This one answers the size from a table read once for each control size.
struct NativeCheckbox: NSViewRepresentable {
    @Binding var isOn: Bool
    /// What VoiceOver reads, since the checkbox has no title of its own.
    let label: String
    var help: String?

    func makeCoordinator() -> Coordinator {
        Coordinator(isOn: $isOn)
    }

    func makeNSView(context: Context) -> NSButton {
        let button = Self.checkbox()
        button.target = context.coordinator
        button.action = #selector(Coordinator.toggle(_:))
        update(button, in: context)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.isOn = $isOn
        update(button, in: context)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSButton, context: Context) -> CGSize? {
        Self.size(at: nsView.controlSize)
    }

    private func update(_ button: NSButton, in context: Context) {
        let state: NSControl.StateValue = isOn ? .on : .off
        if button.state != state { button.state = state }
        let size = NSControl.ControlSize(context.environment.controlSize) ?? .regular
        if button.controlSize != size { button.controlSize = size }
        if button.isEnabled != context.environment.isEnabled { button.isEnabled = context.environment.isEnabled }
        if button.accessibilityLabel() != label { button.setAccessibilityLabel(label) }
        if button.toolTip != help { button.toolTip = help }
    }

    /// AppKit's standard checkbox with no title. `init(checkboxWithTitle:target:action:)` makes the same button but
    /// sizes it to its title twice on the way, and a list makes one for every row that scrolls into view.
    private static func checkbox() -> NSButton {
        let button = NSButton(frame: .zero)
        button.setButtonType(.switch)
        button.title = ""
        return button
    }

    private static var sizes: [NSControl.ControlSize: CGSize] = [:]

    private static func size(at controlSize: NSControl.ControlSize) -> CGSize {
        if let size = sizes[controlSize] { return size }
        let button = checkbox()
        button.controlSize = controlSize
        let size = button.intrinsicContentSize
        sizes[controlSize] = size
        return size
    }

    final class Coordinator: NSObject {
        var isOn: Binding<Bool>

        init(isOn: Binding<Bool>) {
            self.isOn = isOn
        }

        @objc func toggle(_ button: NSButton) {
            isOn.wrappedValue = button.state == .on
        }
    }
}
