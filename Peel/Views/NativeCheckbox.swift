import AppKit
import PeelCore
import SwiftUI

/// AppKit's checkbox, for the rows of a list. A checkbox `Toggle` is the same button, but SwiftUI asks it for its size
/// each time the list measures a row, which drops frames while a long list scrolls. This one reads its size once.
struct NativeCheckbox: NSViewRepresentable {
    @Binding var isOn: Bool
    let label: String
    var help: String?
    var hint: String?

    func makeCoordinator() -> Coordinator {
        Coordinator(isOn: $isOn)
    }

    func makeNSView(context: Context) -> Host {
        let host = Host()
        host.button.target = context.coordinator
        host.button.action = #selector(Coordinator.toggle(_:))
        update(host.button, in: context)
        return host
    }

    func updateNSView(_ host: Host, context: Context) {
        context.coordinator.isOn = $isOn
        update(host.button, in: context)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView host: Host, context: Context) -> CGSize? {
        Self.size(at: host.button.controlSize)
    }

    /// Holds the button one level below the view SwiftUI hosts, so the button answers VoiceOver's Show Menu itself.
    /// SwiftUI answers it for the view it hosts and opens nothing while that view is disabled, which would take the
    /// row's menu away from a row that cannot be selected.
    final class Host: NSView {
        let button = NativeCheckbox.checkbox()

        init() {
            super.init(frame: .zero)
            button.autoresizingMask = [.width, .height]
            addSubview(button)
        }

        required init?(coder: NSCoder) {
            nil
        }
    }

    private func update(_ button: NSButton, in context: Context) {
        let state: NSControl.StateValue = isOn ? .on : .off
        if button.state != state { button.state = state }
        let size = NSControl.ControlSize(context.environment.controlSize) ?? .regular
        if button.controlSize != size { button.controlSize = size }
        if button.isEnabled != context.environment.isEnabled { button.isEnabled = context.environment.isEnabled }
        if button.accessibilityLabel() != label { button.setAccessibilityLabel(label) }
        if button.toolTip != help { button.toolTip = help }
        if button.accessibilityHelp() != hint ?? help { button.setAccessibilityHelp(hint ?? help) }
    }

    /// Not `init(checkboxWithTitle:target:action:)`, which sizes the button to its title twice on the way.
    private static func checkbox() -> NSButton {
        let button = RowCheckboxButton(frame: .zero)
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

extension VerticalAlignment {
    /// The middle of the first line of a checkbox's title, which the checkbox is centered on.
    nonisolated static let checkboxTitleLine = VerticalAlignment(CheckboxTitleLine.self)

    private nonisolated enum CheckboxTitleLine: AlignmentID {
        static func defaultValue(in dimensions: ViewDimensions) -> CGFloat {
            dimensions[VerticalAlignment.center]
        }
    }
}

extension View {
    /// Draws this view as a checkbox's title, dimmed two levels when disabled, as SwiftUI dims its checkbox's label.
    func checkboxTitle() -> some View {
        modifier(CheckboxTitleStyle())
    }

    /// Marks this text as the first line of a checkbox's title, whose middle is its baseline less half its cap height,
    /// where AppKit centers a checkbox beside its title.
    func checkboxTitleLine() -> some View {
        modifier(CheckboxTitleLineGuide())
    }
}

private struct CheckboxTitleStyle: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        if isEnabled {
            content
        } else {
            content.foregroundStyle(.tertiary, .quaternary, .quinary)
        }
    }
}

private struct CheckboxTitleLineGuide: ViewModifier {
    @Environment(\.font) private var font
    @Environment(\.fontResolutionContext) private var fontContext

    func body(content: Content) -> some View {
        let capHeight = CTFontGetCapHeight((font ?? .body).resolve(in: fontContext).ctFont)
        content.alignmentGuide(.checkboxTitleLine) { $0[.firstTextBaseline] - capHeight / 2 }
    }
}
