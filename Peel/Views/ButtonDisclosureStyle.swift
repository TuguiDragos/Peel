import SwiftUI

/// A disclosure opened by a button, so VoiceOver, Voice Control and Switch Control can open it: in a `Form` the
/// system's disclosure triangle offers them no action. Its content is built only while it is open.
struct ButtonDisclosureStyle: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        ButtonDisclosure(configuration: configuration)
    }
}

private struct ButtonDisclosure: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let configuration: DisclosureGroupStyleConfiguration

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(reduceMotion ? nil : Motion.step.animation) {
                    configuration.$isExpanded.wrappedValue.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(configuration.isExpanded ? 90 : 0))
                        .accessibilityHidden(true)
                    configuration.label
                }
                .minimumTarget()
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            if configuration.isExpanded {
                configuration.content
            }
        }
    }
}
