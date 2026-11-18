import PeelCore
import SwiftUI

/// Over a list whose scan couldn't look into some folders: how many, why when that is known, and the folders under
/// Show Folders, since something may be there that isn't listed.
struct UnreadableFoldersNotice: View {
    @Environment(HomeModel.self) private var home
    let folders: [URL]
    var needsFullDiskAccess = false
    @State private var counted = ClosedByPermissions()

    var body: some View {
        Notice(
            title: Text("Peel did not read ^[\(folders.count) folder](inflect: true)"),
            detail: Text(
                verbatim: Self.detail(
                    count: folders.count, closed: counted.count(of: folders), needsFullDiskAccess: needsFullDiskAccess,
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

    /// Why Peel did not read the folders, when that is known, and what that means for the list, in one sentence, or in
    /// two when Full Disk Access would open only some of them.
    static func detail(count: Int, closed: Int, needsFullDiskAccess: Bool, reopens: Bool = false) -> String {
        let why: String = if needsFullDiskAccess, closed > 0 {
            String(localized: "macOS keeps Peel out of the folders it protects until Peel has Full Disk Access.")
                + " " + String(localized: "Something there may not be listed.")
        } else if needsFullDiskAccess {
            count == 1
                ? String(localized: "macOS keeps Peel out of it until Peel has Full Disk Access, so something there may not be listed.")
                : String(localized: "macOS keeps Peel out of them until Peel has Full Disk Access, so something there may not be listed.")
        } else if closed == 0 {
            String(localized: "Something there may not be listed.")
        } else if closed < count {
            String(localized: "Some of them have permissions of their own that keep your account out, so something there may not be listed.")
        } else {
            count == 1
                ? String(localized: "Its own permissions keep your account out, so something there may not be listed.")
                : String(localized: "Their own permissions keep your account out, so something there may not be listed.")
        }
        return ([why] + (reopens ? [HomeModel.reopenForFullDiskAccess] : [])).joined(separator: "\n\n")
    }

    /// Why Peel did not read the folders, alone, for a page whose own sentence says what that means, or nil when the
    /// reason isn't known.
    static func reason(count: Int, closed: Int, needsFullDiskAccess: Bool) -> String? {
        if needsFullDiskAccess {
            return String(localized: "macOS keeps Peel out of the folders it protects until Peel has Full Disk Access.")
        }
        if closed == 0 { return nil }
        if closed < count {
            return String(localized: "Some of them have permissions of their own that keep your account out.")
        }
        return count == 1
            ? String(localized: "Its own permissions keep your account out.")
            : String(localized: "Their own permissions keep your account out.")
    }
}

/// What Peel did not read, said under a page's own message, with why when that is known.
struct UnreadableFoldersDetail: View {
    let folders: [URL]
    var needsFullDiskAccess = false
    /// The page's own sentence about them, in place of the shared one.
    var saying: Text?
    @State private var counted = ClosedByPermissions()

    private var text: Text {
        let closed = counted.count(of: folders)
        guard let saying else {
            let why = UnreadableFoldersNotice.detail(
                count: folders.count, closed: closed, needsFullDiskAccess: needsFullDiskAccess
            )
            return Text("\(Text("Peel did not read ^[\(folders.count) folder](inflect: true)."))\n\n\(Text(verbatim: why))")
        }
        guard let why = UnreadableFoldersNotice.reason(
            count: folders.count, closed: closed, needsFullDiskAccess: needsFullDiskAccess
        ) else { return saying }
        return Text("\(saying)\n\n\(Text(verbatim: why))")
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

/// What can be done about folders a scan couldn't read: see them, each with Show in Finder, and turn on Full Disk
/// Access when macOS's privacy protection kept Peel out of one.
struct UnreadableFoldersActions: View {
    @Environment(HomeModel.self) private var home
    let folders: [URL]
    let needsFullDiskAccess: Bool
    @State private var isShowingFolders = false

    var body: some View {
        Button("Show Folders") { isShowingFolders = true }
            .popover(isPresented: $isShowingFolders, arrowEdge: .bottom) {
                UnreadableFoldersList(folders: folders, needsFullDiskAccess: needsFullDiskAccess)
            }
        if needsFullDiskAccess {
            Button("Turn On Full Disk Access") { home.openFullDiskAccessSettings() }
            // Full Disk Access applies only to a new process, so once it may have been given, Peel offers to reopen.
            if home.needsRelaunchForFullDiskAccess {
                Button("Reopen Peel") { home.relaunch() }
            }
        }
    }
}

/// The folders a scan couldn't read, each with Show in Finder, and what more there is to know about them.
struct UnreadableFoldersList: View {
    let folders: [URL]
    let needsFullDiskAccess: Bool
    @State private var counted = ClosedByPermissions()

    /// The folders macOS lets a person allow one by one, apart from Full Disk Access.
    private static let asksForItsFolderAlone = ["~/Desktop", "~/Documents", "~/Downloads"]

    private var notes: [String] {
        let paths = folders.map(\.abbreviatedPath)
        let alone = needsFullDiskAccess && paths.contains(where: Self.asksForItsFolderAlone.contains)
            ? [String(localized: "For Desktop, Documents, or Downloads alone, allow Peel in System Settings > Privacy & Security > Files & Folders.")]
            : []
        let permissions = needsFullDiskAccess && counted.count(of: folders) > 0
            ? [String(localized: "Some of these folders have permissions of their own, which Full Disk Access does not change.")]
            : []
        return alone + permissions
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(folders, id: \.self) { folder in
                        HStack(spacing: 8) {
                            Text(verbatim: folder.abbreviatedPath)
                                .font(.callout)
                                .lineLimit(2)
                                .truncationMode(.middle)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            ShowInFinderButton(url: folder)
                        }
                    }
                }
            }
            .frame(maxHeight: 320)
            .fixedSize(horizontal: false, vertical: true)
            ForEach(notes, id: \.self) { note in
                Text(verbatim: note)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                CopyButton(text: folders.map(\.abbreviatedPath).joined(separator: "\n"), title: "Copy Details")
            }
        }
        .padding(14)
        .frame(width: 400)
        .task(id: folders) { counted = await .counting(folders) }
    }
}
