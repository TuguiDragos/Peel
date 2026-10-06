import SwiftUI

/// What Homebrew writes while it upgrades, shown as it comes, with a way to stop it. An upgrade has no time limit,
/// since Homebrew builds some packages on this Mac, so the person decides when it has run long enough.
struct HomebrewProgressView: View {
    @Environment(HomebrewLibrary.self) private var homebrew
    @State private var isConfirmingStop = false

    var body: some View {
        ScrollView {
            Text(verbatim: homebrew.progress ?? "")
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
        }
        .defaultScrollAnchor(.bottom)
        // What runs and its Stop sit in this column's section of the title bar. With the output reaching up to the
        // title bar, macOS draws no line under it, as on every other page.
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Running Homebrew…")
                        .font(.headline)
                }
            }
            .sharedBackgroundVisibility(.hidden)
            ToolbarSpacer(.flexible, placement: .primaryAction)
            ToolbarItem(placement: .primaryAction) {
                Button("Stop", systemImage: "stop.fill") { isConfirmingStop = true }
                    .disabled(homebrew.isStopping)
            }
        }
        .confirmationDialog("Stop Homebrew?", isPresented: $isConfirmingStop) {
            Button("Stop", role: .destructive) { homebrew.stopUpgrade() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("A package Homebrew is in the middle of installing may be left half installed, and may need installing again.")
        }
    }

}
