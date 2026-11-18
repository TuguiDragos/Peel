import PeelCore
import SwiftUI

/// Opens a maker's uninstaller once its signature is read again whole and holds, and says why when it doesn't.
struct OpenUninstallerButton: View {
    let uninstaller: URL
    /// The team that signs the app the uninstaller removes.
    let team: String?
    @State private var isChecking = false
    @State private var isRefused = false

    var body: some View {
        Button("Open Uninstaller") {
            isChecking = true
            Task {
                if await VendorRemoval.mayOpen(uninstaller, signedBy: team) {
                    NSWorkspace.shared.open(uninstaller)
                } else {
                    isRefused = true
                }
                isChecking = false
            }
        }
        .disabled(isChecking)
        .alert("Peel did not open the uninstaller", isPresented: $isRefused) {
            Button("OK") {}
        } message: {
            Text("It changed after its maker signed it, so Peel cannot vouch for it.")
        }
    }
}
