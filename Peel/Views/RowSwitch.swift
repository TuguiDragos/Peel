import SwiftUI

/// The switch at the end of a Tweaks or Terminal row, named for VoiceOver by the row's title.
struct RowSwitch: View {
    let title: Text
    @Binding var isOn: Bool

    var body: some View {
        Group {
            if #available(macOS 27, *) {
                // An empty label rather than a hidden one: SwiftUI then shows VoiceOver AppKit's own switch rather
                // than a stand-in, which leaves AppKit's switch outside the accessibility tree.
                Toggle(isOn: $isOn) { Text(verbatim: "") }
                    .accessibilityLabel(title)
            } else {
                Toggle(isOn: $isOn) { EmptyView() }
                    .labelsHidden()
                    .accessibilityRepresentation {
                        Toggle(isOn: $isOn) { title }
                    }
            }
        }
        // The row's title takes its room first: with a label, even an empty one, a switch asks for far more width than
        // it draws.
        .layoutPriority(-1)
    }
}
