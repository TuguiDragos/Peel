import PeelCore
import SwiftUI

/// Opens a maker's uninstaller once its signature is read again whole and holds, and says why when it doesn't.
struct OpenUninstallerButton: View {
    let uninstaller: URL
    /// The team that signs the app the uninstaller removes.
    let team: String?
    @State private var isChecking = false
    @State private var why: Text?

    var body: some View {
        Button("Open Uninstaller") {
            isChecking = true
            Task {
                why = await Self.open(uninstaller, signedBy: team)
                isChecking = false
            }
        }
        .disabled(isChecking)
        .alert(
            "Peel did not open the uninstaller",
            isPresented: Binding(get: { why != nil }, set: { if !$0 { why = nil } })
        ) {
            Button("OK") {}
        } message: {
            why
        }
    }

    /// Opens the uninstaller, or says why it didn't.
    private static func open(_ uninstaller: URL, signedBy team: String?) async -> Text? {
        switch await VendorRemoval.opening(uninstaller, signedBy: team) {
        case .gone:
            return Text("It is no longer on this Mac.")
        case .notVouchedFor:
            return Text("It changed after its maker signed it, so Peel cannot vouch for it.")
        case .allowed:
            do {
                _ = try await NSWorkspace.shared.openApplication(
                    at: uninstaller, configuration: NSWorkspace.OpenConfiguration()
                )
                return nil
            } catch {
                return Text(verbatim: error.localizedDescription)
            }
        }
    }
}

/// Opens a new Terminal window at the home folder, where a command is pasted, and says why when it can't.
struct OpenTerminalButton: View {
    @State private var why: String?

    var body: some View {
        Button("Open Terminal") {
            let isTerminalOpen = TerminalSettings().isTerminalOpen
            Task {
                do {
                    try await TerminalLibrary.openNewWindow(isTerminalOpen: isTerminalOpen)
                } catch {
                    why = error.localizedDescription
                }
            }
        }
        .alert(
            "Peel could not open Terminal", isPresented: Binding(get: { why != nil }, set: { if !$0 { why = nil } })
        ) {
            Button("OK") {}
        } message: {
            Text(verbatim: why ?? "")
        }
    }
}

/// Opens an app whose own window holds its maker's uninstall step, and says why when it can't.
struct OpenAppButton: View {
    let app: URL
    let name: String
    @State private var why: String?

    /// What VoiceOver calls it: the words it shows, which Voice Control goes by, then the app.
    static func spokenName(of name: String) -> String {
        String(localized: "\(String(localized: "Open App")): \(name)")
    }

    var body: some View {
        Button("Open App") {
            Task {
                do {
                    _ = try await NSWorkspace.shared.openApplication(
                        at: app, configuration: NSWorkspace.OpenConfiguration()
                    )
                } catch {
                    why = error.localizedDescription
                }
            }
        }
        .accessibilityLabel(Text(verbatim: Self.spokenName(of: name)))
        .alert(
            Text("Peel could not open \(name)"), isPresented: Binding(get: { why != nil }, set: { if !$0 { why = nil } })
        ) {
            Button("OK") {}
        } message: {
            Text(verbatim: why ?? "")
        }
    }
}
