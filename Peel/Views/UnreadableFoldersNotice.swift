import PeelCore
import SwiftUI

/// Over a list whose scan couldn't look into some folders: it names them, since something may be there that isn't
/// listed, and says when Full Disk Access would open one of them.
struct UnreadableFoldersNotice: View {
    @Environment(HomeModel.self) private var home
    let folders: [URL]
    var needsFullDiskAccess = false
    @State private var counted = ClosedByPermissions()

    private var closed: Int {
        counted.count(of: folders)
    }

    var body: some View {
        Notice(
            title: folders.count == 1 ? Text("A folder couldn’t be read") : Text("Some folders couldn’t be read"),
            detail: Text(
                verbatim: Self.detail(
                    naming: folders.map(\.abbreviatedPath), closed: closed, needsFullDiskAccess: needsFullDiskAccess,
                    reopens: needsFullDiskAccess && home.needsRelaunchForFullDiskAccess
                )
            ),
            kind: needsFullDiskAccess ? .problem : .note
        ) {
            UnreadableFoldersActions(folders: folders, needsFullDiskAccess: needsFullDiskAccess)
        }
        .padding(.vertical, 6)
        .listRowSeparator(.hidden)
        .task(id: folders) { counted = await .counting(folders) }
    }

    /// The folders macOS lets a person allow one by one, apart from Full Disk Access.
    private static let asksForItsFolderAlone = ["~/Desktop", "~/Documents", "~/Downloads"]

    /// The folders, the first few by path, why when their permissions are why, then the advice when Full Disk Access
    /// would open one of them, and why to reopen Peel while Peel offers it.
    static func detail(
        naming paths: [String], closed: Int, needsFullDiskAccess: Bool, reopens: Bool = false
    ) -> String {
        let named = paths.isEmpty
            ? [] : [String(localized: "Peel couldn’t look inside \(RemovalFailureAlert.listedFolders(paths)), so something may be there that isn’t listed here.")]
        let why = [whyNotRead(closed: closed, of: paths.count)].compactMap(\.self)
        let advice = needsFullDiskAccess
            ? [String(localized: "macOS keeps Peel out of the folders it protects until Peel has Full Disk Access. Turn it on from Home.")] : []
        let foldersAlone = !paths.filter(asksForItsFolderAlone.contains).isEmpty && needsFullDiskAccess
            ? [String(localized: "For Desktop, Documents, or Downloads alone, allow Peel in System Settings > Privacy & Security > Files & Folders.")]
            : []
        let reopen = reopens ? [HomeModel.reopenForFullDiskAccess] : []
        return (named + why + advice + foldersAlone + reopen).joined(separator: "\n\n")
    }

    /// The sentence that says the permissions kept Peel out, given how many of how many items they closed.
    static func whyNotRead(closed: Int, of count: Int) -> String? {
        if closed == 0 { return nil }
        if closed < count {
            return String(localized: "Some of these folders have permissions of their own that keep your account out of them. Full Disk Access lets Peel past macOS’s privacy protections, not past a folder’s own permissions.")
        }
        return closed == 1
            ? String(localized: "The folder’s own permissions keep your account out of it. Full Disk Access lets Peel past macOS’s privacy protections, not past a folder’s own permissions.")
            : String(localized: "These folders’ own permissions keep your account out of them. Full Disk Access lets Peel past macOS’s privacy protections, not past a folder’s own permissions.")
    }
}

/// What Peel couldn't read, said under a page's own message, with why when the permissions of `folders` are why.
struct UnreadableFoldersDetail: View {
    let folders: [URL]
    var needsFullDiskAccess = false
    /// The page's own sentence naming them, in place of the shared one.
    var saying: Text?
    @State private var counted = ClosedByPermissions()

    private var closed: Int {
        counted.count(of: folders)
    }

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
            ? Text("macOS keeps Peel out of the folders it protects until Peel has Full Disk Access. Turn it on from Home.") : nil
        return [why, advice].compactMap(\.self).reduce(saying) { Text("\($0)\n\n\($1)") }
    }

    var body: some View {
        text
            .task(id: folders) { counted = await .counting(folders) }
    }
}

/// How many of some folders their permissions keep this account out of, kept with the folders it was counted for: when
/// the folders change, the count of the ones before would give a reason that is theirs.
struct ClosedByPermissions {
    private var folders: [URL] = []
    private var count = 0

    /// The count for `folders`, or none until they have been counted.
    func count(of folders: [URL]) -> Int {
        self.folders == folders ? count : 0
    }

    static func counting(_ folders: [URL]) async -> ClosedByPermissions {
        ClosedByPermissions(folders: folders, count: await FileAccess.closedByPermissions(among: folders))
    }
}

/// What can be done about folders a scan couldn't read: Full Disk Access when macOS's privacy protection kept Peel out
/// of one, and the whole list on the pasteboard when a message names only the first few.
struct UnreadableFoldersActions: View {
    @Environment(HomeModel.self) private var home
    let folders: [URL]
    let needsFullDiskAccess: Bool

    var body: some View {
        if folders.count > RemovalFailureAlert.mostListed {
            CopyButton(text: folders.map(\.abbreviatedPath).joined(separator: "\n"), title: "Copy Details")
        }
        if needsFullDiskAccess {
            Button("Open Home") { Navigator.shared.requestedTool = .home }
            // Full Disk Access applies only to a new process, so once it may have been given, Peel offers to reopen.
            if home.needsRelaunchForFullDiskAccess {
                Button("Reopen Peel") { home.relaunch() }
            }
        }
    }
}
