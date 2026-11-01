import PeelCore
import SwiftUI

/// Over a list whose scan couldn't look into some folders: it names them, since something may be there that isn't
/// listed, and says when Full Disk Access would open one of them.
struct UnreadableFoldersNotice: View {
    let folders: [URL]
    var needsFullDiskAccess = false
    @State private var closed = 0

    var body: some View {
        Notice(
            title: Text("Some folders couldn’t be read"),
            detail: Text(
                verbatim: Self.detail(
                    naming: folders.map(\.abbreviatedPath), closed: closed, needsFullDiskAccess: needsFullDiskAccess
                )
            ),
            kind: needsFullDiskAccess ? .problem : .note
        ) {
            UnreadableFoldersActions(folders: folders, needsFullDiskAccess: needsFullDiskAccess)
        }
        .padding(.vertical, 6)
        .listRowSeparator(.hidden)
        .task(id: folders) { closed = await FileAccess.closedByPermissions(among: folders) }
    }

    /// The folders macOS lets a person allow one by one, apart from Full Disk Access.
    private static let asksForItsFolderAlone = ["~/Desktop", "~/Documents", "~/Downloads"]

    /// The folders, the first few by path, why when their permissions are why, and then the advice when Full Disk
    /// Access would open one of them.
    static func detail(naming paths: [String], closed: Int, needsFullDiskAccess: Bool) -> String {
        let named = paths.isEmpty
            ? [] : [String(localized: "Peel couldn’t look inside \(RemovalFailureAlert.listedFolders(paths)), so something may be there that isn’t listed here.")]
        let why = [whyNotRead(closed: closed, of: paths.count)].compactMap(\.self)
        let advice = needsFullDiskAccess
            ? [String(localized: "Give Peel Full Disk Access so it can read the folders macOS protects.")] : []
        let foldersAlone = !paths.filter(asksForItsFolderAlone.contains).isEmpty && needsFullDiskAccess
            ? [String(localized: "For Desktop, Documents, or Downloads alone, allow Peel in System Settings > Privacy & Security > Files & Folders.")]
            : []
        return (named + why + advice + foldersAlone).joined(separator: "\n\n")
    }

    /// The sentence that says the permissions kept Peel out, given how many of how many items they closed.
    static func whyNotRead(closed: Int, of count: Int) -> String? {
        if closed == 0 { return nil }
        if closed < count { return String(localized: "The permissions of some of them don’t let your account read them.") }
        return closed == 1
            ? String(localized: "Its permissions don’t let your account read it.")
            : String(localized: "Their permissions don’t let your account read them.")
    }
}

/// What Peel couldn't read, said under a page's own message, with why when the permissions of `folders` are why.
struct UnreadableFoldersDetail: View {
    let folders: [URL]
    var needsFullDiskAccess = false
    /// The page's own sentence naming them, in place of the shared one.
    var saying: Text?
    @State private var closed = 0

    private var text: Text {
        guard let saying else {
            return Text(
                verbatim: UnreadableFoldersNotice.detail(
                    naming: folders.map(\.abbreviatedPath), closed: closed, needsFullDiskAccess: needsFullDiskAccess
                )
            )
        }
        let why = UnreadableFoldersNotice.whyNotRead(closed: closed, of: folders.count).map { Text(verbatim: $0) }
        let advice = needsFullDiskAccess
            ? Text("Give Peel Full Disk Access so it can read the folders macOS protects.") : nil
        return [why, advice].compactMap(\.self).reduce(saying) { Text("\($0)\n\n\($1)") }
    }

    var body: some View {
        text
            .task(id: folders) { closed = await FileAccess.closedByPermissions(among: folders) }
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
