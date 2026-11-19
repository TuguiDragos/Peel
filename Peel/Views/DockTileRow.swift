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
            InfoNote(name: String(localized: "Remove from the Dock"), detail: Text(Self.note(for: apps)))
        }
    }

    static func note(for apps: Apps) -> LocalizedStringResource {
        switch apps {
        case .moved:
            "The Dock keeps the icon of a gone app as a question mark. Peel takes it out once the app is in the Trash, and the Dock restarts. Put back from History, the app gets its icon back."
        case .alreadyInTheTrash:
            "The Dock keeps the icon of a gone app as a question mark. Peel takes it out once what the app left is in the Trash, and the Dock restarts. The app was already in the Trash, so History does not bring its icon back."
        case .both:
            "The Dock keeps the icon of a gone app as a question mark. Peel takes it out once the app is in the Trash, and the Dock restarts. Put back from History, the app gets its icon back, unless it was already in the Trash."
        }
    }
}
