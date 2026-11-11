import SwiftUI

/// The bar that floats at the foot of a page: a reading of what is selected in a glass capsule, and the button
/// that acts on it, a button with a symbol.
struct FloatingBar<Reading: View, Action: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var glass
    @ViewBuilder let reading: Reading
    @ViewBuilder let action: Action

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            // Where the words leave no room for the button's title, as a longer language's can in the narrowest
            // column, the button shows its symbol alone, as in a toolbar, and VoiceOver still reads its title.
            ViewThatFits(in: .horizontal) {
                row(symbolOnly: false)
                row(symbolOnly: true)
            }
        }
        // Apple: "Instead of fading, Liquid Glass objects materialize in and out". A transition is not an
        // animation, so `.motion` cannot gate it and Reduce Motion is asked here by hand, as `.symbolEffect`
        // is in `RescanButton`.
        .glassEffectTransition(reduceMotion ? .identity : .matchedGeometry)
        .padding(.bottom, 16)
    }

    private func row(symbolOnly: Bool) -> some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                reading
            }
            // The capsule is one line tall. Without this a narrow column wraps the words inside it,
            // which breaks them mid-word and pushes the second line out of the fixed height.
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 18)
            .frame(height: 40)
            .glassEffect()
            .glassEffectID("reading", in: glass)
            // The figure and its word are one reading, "303 kB Selected", as `TotalLabel` reads its total.
            .accessibilityElement(children: .combine)

            Group {
                if symbolOnly {
                    action.labelStyle(.iconOnly)
                } else {
                    action
                }
            }
            .buttonStyle(.glassProminent)
            .controlSize(.extraLarge)
            .glassEffectID("action", in: glass)
        }
    }
}
