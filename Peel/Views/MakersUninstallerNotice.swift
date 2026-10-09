import PeelCore
import SwiftUI

/// The note on the page of a security or management agent: its maker's own uninstaller removes it whole, so Peel
/// leaves it and its files where they are and offers the maker's step and instructions instead.
struct MakersUninstallerNotice: View {
    let app: String
    let uninstaller: MakersUninstaller

    var body: some View {
        Notice(
            title: Text("Removed with \(uninstaller.maker)’s own uninstaller"),
            detail: Text("\(uninstaller.maker) documents removing \(app) with its own uninstaller, which also takes what it keeps in the system and the settings that manage it. Moved from here, those would stay behind, so Peel leaves it and its files where they are."),
            kind: .note
        ) {
            switch uninstaller.step {
            case .command(let command):
                CopyButton(text: command, title: "Copy Uninstall Command")
            case .uninstaller(let url):
                Button("Open Uninstaller") { NSWorkspace.shared.open(url) }
                    .disabled(!FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
            }
            Link("\(uninstaller.maker)’s Instructions", destination: uninstaller.instructions)
        }
    }
}
