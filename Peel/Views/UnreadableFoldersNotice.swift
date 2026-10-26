import SwiftUI

/// Over a list whose scan couldn't look into some folders: it names them, since something may be there that isn't
/// listed, and says when Full Disk Access would open one of them.
struct UnreadableFoldersNotice: View {
    let folders: [URL]
    var needsFullDiskAccess = false

    var body: some View {
        Notice(
            title: Text("Some folders couldn’t be read"),
            detail: Text(
                verbatim: Self.detail(naming: folders.map(\.abbreviatedPath), needsFullDiskAccess: needsFullDiskAccess)
            ),
            kind: needsFullDiskAccess ? .problem : .note
        ) {
            UnreadableFoldersActions(folders: folders, needsFullDiskAccess: needsFullDiskAccess)
        }
        .padding(.vertical, 6)
        .listRowSeparator(.hidden)
    }

    /// The folders, the first few by path, and then the advice when Full Disk Access would open one of them.
    static func detail(naming paths: [String], needsFullDiskAccess: Bool) -> String {
        let named = paths.isEmpty
            ? [] : [String(localized: "Peel couldn’t look inside \(RemovalFailureAlert.listedFolders(paths)), so something may be there that isn’t listed here.")]
        let advice = needsFullDiskAccess
            ? [String(localized: "Give Peel Full Disk Access so it can read the folders macOS protects.")] : []
        return (named + advice).joined(separator: "\n\n")
    }
}

/// What can be done about folders a scan couldn't read: Full Disk Access when macOS's privacy protection kept Peel out
/// of one, and the whole list on the pasteboard when a message names only the first few.
struct UnreadableFoldersActions: View {
    @Environment(HomeModel.self) private var home
    let folders: [URL]
    let needsFullDiskAccess: Bool

    var body: some View {
        if needsFullDiskAccess {
            // Full Disk Access applies only to a new process, so once it may have been given, Peel offers to reopen.
            if home.needsRelaunchForFullDiskAccess {
                Button("Reopen Peel") { home.relaunch() }
            }
            Button("Open System Settings") { home.openFullDiskAccessSettings() }
        }
        if folders.count > RemovalFailureAlert.mostListed {
            CopyButton(text: folders.map(\.abbreviatedPath).joined(separator: "\n"), title: "Copy Details")
        }
    }
}
