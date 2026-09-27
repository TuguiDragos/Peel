import SwiftUI

extension View {
    /// The alert that offers to force what did not quit before a removal. It closes by itself once they have.
    func forceQuitOffer(_ quitting: QuitBeforeRemoving) -> some View {
        alert(Text("\(quitting.names) didn’t quit."), isPresented: Bindable(quitting).isOfferingToForce) {
            Button("Force Quit", role: .destructive) { quitting.forceQuit() }
            Button("Cancel", role: .cancel) { quitting.giveUp() }
        } message: {
            Text("An app may be waiting for you, for example to save your work. Force Quit closes what is still open at once, and what isn’t saved is lost.")
        }
    }
}
