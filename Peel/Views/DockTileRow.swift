import SwiftUI

/// A checkbox that also takes the removed apps' icons out of the Dock, selected unless the user deselects it: a gone
/// app's icon is only a question mark.
struct DockTileRow: View {
    @Binding var isOn: Bool
    let apps: DockTileOption.Apps

    var body: some View {
        HStack(spacing: 5) {
            DockTileOption(isOn: $isOn, apps: apps)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .listRowSeparator(.hidden)
    }
}

/// The checkbox and its circled i, for a row of their own or beside another option.
struct DockTileOption: View {
    /// Whose icons go: the apps Peel moves, whose icons History puts back with them, the apps already in the Trash,
    /// which History never moved, or both.
    enum Apps {
        case moved, alreadyInTheTrash, both
    }

    @Binding var isOn: Bool
    let apps: Apps

    var body: some View {
        HStack(spacing: 5) {
            Toggle(isOn: $isOn) {
                Text("Also remove from the Dock")
            }
            .toggleStyle(.checkbox)
            InfoNote(name: String(localized: "Remove from the Dock"), detail: detail)
        }
    }

    private var detail: Text {
        switch apps {
        case .moved:
            Text("The Dock keeps an app’s icon after the app is gone, as a question mark. If this is selected, Peel takes the icon out once the app is in the Trash, and the Dock restarts. Putting the app back from History puts its icon back where it was.")
        case .alreadyInTheTrash:
            Text("The Dock keeps an app’s icon after the app is gone, as a question mark. If this is selected, Peel takes the icon out once the files the app left behind are in the Trash, and the Dock restarts. The app was already in the Trash, so History doesn’t put its icon back.")
        case .both:
            Text("The Dock keeps an app’s icon after the app is gone, as a question mark. If this is selected, Peel takes the icon out once the app is in the Trash, and the Dock restarts. Putting the app back from History puts its icon back where it was, but an app that was already in the Trash doesn’t get its icon back.")
        }
    }
}
