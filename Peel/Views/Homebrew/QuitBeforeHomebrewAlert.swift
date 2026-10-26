import SwiftUI

extension View {
    /// The alerts that quit a cask's apps before Homebrew upgrades or uninstalls it, as an app's page does before a
    /// removal.
    func quitBeforeHomebrew(_ quitting: QuitBeforeRemoving, upgrading: Bool) -> some View {
        alert(
            upgrading ? Text("Quit \(quitting.names) before upgrading.") : Text("Quit \(quitting.names) before uninstalling."),
            isPresented: Bindable(quitting).isAsking
        ) {
            Button("Quit \(quitting.names)") { quitting.quit() }
            Button("Cancel", role: .cancel) { quitting.giveUp() }
        } message: {
            upgrading
                ? Text("Homebrew replaces what it upgrades, even while it runs, so Peel quits it first and opens it again once Homebrew is done.")
                : Text("Homebrew deletes what it uninstalls, even while it runs, so Peel quits it first.")
        }
        .forceQuitOffer(quitting)
        .onDisappear { quitting.giveUp() }
    }
}
