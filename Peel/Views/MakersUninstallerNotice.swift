import PeelCore
import SwiftUI

/// The note on the page of a security or management agent or a VPN, or of such an uninstaller: its maker's own
/// uninstaller removes it whole, so Peel leaves it and its files where they are and offers the maker's step and
/// instructions.
struct MakersUninstallerNotice: View {
    let app: String
    let uninstaller: MakersUninstaller

    var body: some View {
        Notice(title: Text(Self.title(of: uninstaller)), detail: detail, kind: .note) {
            switch uninstaller.step {
            case .command(let command):
                CopyButton(text: command, title: "Copy Uninstall Command")
            case .uninstaller(let url):
                Button("Open Uninstaller") { NSWorkspace.shared.open(url) }
                    .disabled(!FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
            case .inTheApp(let url):
                Button("Open \(app)") { NSWorkspace.shared.open(url) }
            case .onItsDiskImage:
                EmptyView()
            }
            Link("\(uninstaller.maker)’s Instructions", destination: uninstaller.instructions)
        }
    }

    static func title(of uninstaller: MakersUninstaller) -> LocalizedStringResource {
        if let product = uninstaller.removes {
            "\(uninstaller.maker)’s uninstaller for \(product)"
        } else {
            "Removed with \(uninstaller.maker)’s own uninstaller"
        }
    }

    private var detail: Text {
        if let product = uninstaller.removes {
            Text("\(uninstaller.maker) documents removing \(product) by opening this app, which then removes itself too. Moving only this app would leave \(product) behind, so Peel leaves it for you to open.")
        } else {
            Text("\(uninstaller.maker) documents removing \(app) with its own uninstaller, which also takes what it keeps in the system and the settings that manage it. Moved from here, those would stay behind, so Peel leaves it and its files where they are.")
        }
    }
}
