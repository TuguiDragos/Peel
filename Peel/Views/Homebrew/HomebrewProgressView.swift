import SwiftUI

/// What Homebrew writes while it upgrades, shown as it comes, with a way to stop it. An upgrade has no time limit,
/// since Homebrew builds some packages on this Mac, so the person decides when it has run long enough.
struct HomebrewProgressView: View {
    @Environment(HomebrewLibrary.self) private var homebrew
    @State private var isConfirmingStop = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Running Homebrew…")
                    .font(.headline)
                Spacer()
                Button("Stop", systemImage: "stop.fill") { isConfirmingStop = true }
                    .disabled(homebrew.isStopping)
            }
            ScrollView {
                Text(verbatim: homebrew.progress ?? "")
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .defaultScrollAnchor(.bottom)
        }
        .padding(20)
        .confirmationDialog("Stop Homebrew?", isPresented: $isConfirmingStop) {
            Button("Stop", role: .destructive) { homebrew.stopUpgrade() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("A package Homebrew is in the middle of installing may be left half installed, and may need installing again.")
        }
    }

}
