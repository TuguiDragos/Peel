import SwiftUI

struct TurnAllOffBar: View {
    let explanation: LocalizedStringResource
    let isEnabled: Bool
    let turnOff: () -> Void

    var body: some View {
        if #available(macOS 27, *) {
            // macOS 27 tints the whole width behind a bar at the foot of a page, so each part floats on glass of
            // its own instead and the page shows through around them.
            GlassEffectContainer {
                VStack(spacing: 10) {
                    button
                    caption
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .glassEffect(.regular, in: .capsule)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 10)
        } else {
            VStack(spacing: 10) {
                button
                caption
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 10)
        }
    }

    private var button: some View {
        Button("Turn All Off", action: turnOff)
            .buttonStyle(.glass)
            .disabled(!isEnabled)
    }

    private var caption: some View {
        Text(explanation)
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            // Tweaks' English sentence is 642 points wide at this size, so a narrower frame would wrap it.
            .frame(maxWidth: 680)
    }
}

extension View {
    /// Puts the bar at the foot of the page. On macOS 27 it takes room as an inset rather than as a bar, since a
    /// bar gets a tinted background across the page.
    @ViewBuilder
    func turnAllOffBar(_ bar: TurnAllOffBar) -> some View {
        if #available(macOS 27, *) {
            safeAreaInset(edge: .bottom) { bar }
        } else {
            safeAreaBar(edge: .bottom) { bar }
        }
    }
}
