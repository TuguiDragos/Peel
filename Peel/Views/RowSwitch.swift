import SwiftUI

@available(macOS 27, *)
struct RowSwitch: View {
    let title: Text
    @Binding var isOn: Bool

    var body: some View {
        // An empty label rather than a hidden one: SwiftUI then shows VoiceOver AppKit's own switch rather than a
        // stand-in, which leaves AppKit's switch outside the accessibility tree.
        Toggle(isOn: $isOn) { Text(verbatim: "") }
            .accessibilityLabel(title)
    }
}
