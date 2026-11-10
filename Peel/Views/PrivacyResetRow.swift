import SwiftUI

/// A checkbox that also resets the app's privacy permissions during a removal or a reset. It is off until
/// the user selects it, because History can't bring the permissions back.
struct PrivacyResetRow: View {
    @Binding var isOn: Bool
    let detail: Text
    /// False while another copy of the app stays: the checkbox is off and can't be chosen, and its note says why.
    var isAvailable = true

    var body: some View {
        HStack(spacing: 5) {
            PrivacyResetOption(isOn: $isOn, detail: detail, isAvailable: isAvailable)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .listRowSeparator(.hidden)
    }

    /// The explanation for a removal. The reset runs just before the move, because `tccutil` finds an app
    /// through Launch Services, which can't find it once it is in the Trash.
    static var beforeTheMove: Text {
        Text("macOS remembers what an app was allowed to access, such as the camera or the microphone, and keeps that after the app is gone. If this is selected, Peel clears it just before the app goes to the Trash, the last moment macOS can still find the app, so the app asks you again if you install it later. This happens only if the app itself is selected, and no other copy of it stays, since macOS keeps one set of permissions for every copy.")
    }
}

/// The checkbox and its circled i, for a row of their own or beside another option.
struct PrivacyResetOption: View {
    @Binding var isOn: Bool
    let detail: Text
    var isAvailable = true

    var body: some View {
        HStack(spacing: 5) {
            Toggle(isOn: isAvailable ? $isOn : .constant(false)) {
                Text("Also reset privacy permissions")
            }
            .toggleStyle(.checkbox)
            .disabled(!isAvailable)
            InfoNote(name: String(localized: "Reset privacy permissions"), detail: detail)
        }
    }
}
