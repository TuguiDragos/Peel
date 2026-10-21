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
                // Wide enough for the longest sentence a page shows here, which a narrower frame would wrap.
                .frame(maxWidth: 680)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 10)
    }
}
