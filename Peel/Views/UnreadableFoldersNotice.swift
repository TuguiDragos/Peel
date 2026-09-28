import SwiftUI

/// Over a list whose scan could not look into folders that Full Disk Access would not open either, such as one
/// closed by ordinary permissions. It names them, since something may be there that isn't listed.
struct UnreadableFoldersNotice: View {
    let folders: [URL]

    var body: some View {
        Notice(
            title: Text("Some folders couldn’t be read"),
            detail: Text("Peel couldn’t look inside \(folders.map(\.abbreviatedPath).formatted(.list(type: .and))), so something may be there that isn’t listed here."),
            kind: .note
        ) {}
        .padding(.vertical, 6)
        .listRowSeparator(.hidden)
    }
}
