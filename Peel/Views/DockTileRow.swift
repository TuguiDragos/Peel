import SwiftUI

/// A checkbox that also takes the removed apps' icons out of the Dock. It is off until the user selects it,
/// because it changes the Dock.
struct DockTileRow: View {
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 5) {
            Toggle(isOn: $isOn) {
                Text("Also remove from the Dock")
            }
            .toggleStyle(.checkbox)
            InfoNote(
                name: String(localized: "Remove from the Dock"),
                detail: Text("The Dock keeps an app’s icon after the app is gone, as a question mark. If this is selected, Peel takes the icon out once the app is in the Trash, and the Dock restarts. Putting the app back from History puts its icon back where it was.")
            )
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .listRowSeparator(.hidden)
    }
}
