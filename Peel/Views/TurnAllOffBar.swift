import SwiftUI

struct TurnAllOffBar: View {
    let explanation: LocalizedStringResource
    let isEnabled: Bool
    let turnOff: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Button("Turn All Off", action: turnOff)
                .buttonStyle(.glass)
                .disabled(!isEnabled)
            Text(explanation)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                // Tweaks' English sentence is 642 points wide at this size, so a narrower frame would wrap it.
                .frame(maxWidth: 680)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 10)
    }
}

extension View {
    /// Puts the bar at the foot of the page, over a soft edge only while something has scrolled under it.
    @ViewBuilder
    func turnAllOffBar(_ bar: TurnAllOffBar) -> some View {
        if #available(macOS 27, *) {
            modifier(SoftEdgeWhileScrolledUnder(bar: bar))
        } else {
            safeAreaBar(edge: .bottom) { bar }
        }
    }
}

/// macOS 27 gives a bar at the foot of a page a background across the page even when nothing is under it, so the
/// bar takes room as an inset instead. While the content runs on beneath it, a material that blurs it fades in from
/// above the bar, as the soft scroll edge effect does under a bar on macOS 26.
private struct SoftEdgeWhileScrolledUnder: ViewModifier {
    let bar: TurnAllOffBar
    @State private var isOverContent = false

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: Bool.self) { geometry in
                // The visible rect reaches under the bar, so the bar's height is taken off its end.
                geometry.contentSize.height - (geometry.visibleRect.maxY - geometry.contentInsets.bottom) > 1
            } action: { _, isUnder in
                isOverContent = isUnder
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bar
                    .padding(.top, 10)
                    .frame(maxWidth: .infinity)
                    .background(alignment: .bottom) {
                        if isOverContent {
                            Rectangle()
                                .fill(.regularMaterial)
                                .mask(
                                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .center)
                                )
                                .padding(.top, -24)
                                .ignoresSafeArea(edges: .bottom)
                        }
                    }
            }
    }
}
