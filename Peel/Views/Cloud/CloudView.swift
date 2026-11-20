import Accessibility
import AppKit
import PeelCore
import SwiftUI

/// The iCloud Drive page, which frees the local copies of files that are safely in iCloud. Nothing here goes to
/// the Trash or into History: each file stays in iCloud and downloads again when it is opened.
struct CloudView: View {
    @Environment(CloudLibrary.self) private var cloud
    @Environment(HomeModel.self) private var home
    @State private var isConfirming = false
    @State private var freed: BarNotice?
    /// What the last Remove Downloads left as it was, which an alert tells, since the list moves on without it.
    @State private var leftAlone: LeftAlone?
    @State private var isRescanning = false
    @State private var searchText = ""
    /// Opened while browsing; during a search every folder with a match is open unless closed.
    @State private var opened: Set<URL> = []
    @State private var closedInSearch: Set<URL> = []

    var body: some View {
        let listed = cloud.files(matching: searchText)
        let folders = cloud.folders(matching: searchText)
        List {
            header
                .listRowSeparator(.hidden)
            RemovalsHeldBanner(recordsInHistory: false)
            UnreadableFoldersNotice(folders: cloud.notRead)
            if cloud.files?.isEmpty == false, !whyPartlyRead.isEmpty {
                Notice(title: Text(Self.partlyReadTitle), detail: partlyReadNote) {
                    UnreadableFoldersActions(folders: [], needsFullDiskAccess: true)
                }
                .padding(.vertical, 6)
                .listRowSeparator(.hidden)
            }

            if !cloud.refusals.isEmpty {
                Section {
                    let (groups, more) = RemovalFailureAlert.grouped(cloud.refusals, reason: \.explanation)
                    ForEach(groups, id: \.reason) { group in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(group.reason)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            ForEach(group.items) { refusal in
                                Text(refusal.url.abbreviatedPath)
                                    .font(.callout)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                    if more > 0 {
                        HStack {
                            Text(verbatim: String(inflecting: "And ^[\(more) more item](inflect: true)."))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            Spacer()
                            CopyButton(
                                text: RemovalFailureAlert.underTheirReasons(
                                    cloud.refusals.map { ($0.url.fullPath, $0.explanation) }, limit: nil
                                ).joined(separator: "\n\n"),
                                title: "Copy Details"
                            )
                        }
                    }
                } header: {
                    heading("Still Here", "These were left as they are, under the reason they stayed.")
                }
            }

            if !listed.isEmpty {
                let hasNoteColumn = Self.hasNoteColumn(listed)
                Section {
                    ForEach(Array(folders.enumerated()), id: \.element.id) { index, folder in
                        let open = isOpen(folder)
                        CloudFolderRow(
                            folder: folder,
                            rows: selectableRows(folder.files),
                            isOpen: open,
                            hasNoteColumn: hasNoteColumn,
                            isFirst: index == 0,
                            selection: cloud,
                            toggleOpen: { toggle(folder) }
                        )
                        if open {
                            ForEach(folder.files) { file in
                                RemovalRow(
                                    url: file.url,
                                    name: file.name,
                                    icon: .file(file.url),
                                    detail: file.note,
                                    size: file.size,
                                    hasNoteColumn: hasNoteColumn,
                                    selection: cloud, isSelected: cloud.isSelected(file.url)
                                )
                                .padding(.leading, CloudFolderRow.indent)
                            }
                            .listRowSeparator(.hidden)
                        }
                    }
                    .listRowSeparator(.hidden)
                    if cloud.cutShort != nil || cloud.sharedDownloads > 0 {
                        ListNotes {
                            switch cloud.cutShort {
                            case .listIsFull:
                                Text("Peel lists the biggest downloads, up to \(CloudStorage.maximumFiles.formatted()). The next ones show once you remove some of these.")
                            case .ranOutOfTime:
                                HStack(alignment: .firstTextBaseline, spacing: 4) {
                                    Text(Self.tooBigTitle)
                                    InfoNote(
                                        about: Text(Self.tooBigTitle), detail: Text(Self.tooBigNote), isAlbum: false
                                    )
                                }
                            case nil:
                                EmptyView()
                            }
                            sharedDownloadsNote
                        }
                    }
                } header: {
                    SectionHeaderLine {
                        heading("On This Mac and in iCloud", Self.onThisMacNote)
                    } actions: {
                        SelectMenu(
                            list: selectableRows(listed), place: Text(Tool.cloud.title), selection: cloud,
                            removesDownloads: true
                        )
                    }
                }
            }
        }
        .accessibilityLabel(Text(Tool.cloud.title))
        .scrollBarBelowSectionHeaders()
        .dimmedWhileBusy(cloud.isScanning)
        .columnSearch(text: $searchText, prompt: "Search iCloud Drive", when: cloud.files?.isEmpty == false)
        .scanState(phase(listed: listed), scan: cloud.scanRun) {
            if !searchText.isEmpty, cloud.files?.isEmpty == false, listed.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else if cloud.couldNotRead {
                ContentUnavailableView {
                    Label("iCloud Drive Couldn’t Be Read", systemImage: "lock")
                } description: {
                    Text("Peel needs Full Disk Access to see what iCloud files are kept on this Mac. Turn it on from Home.")
                } actions: {
                    Button("Open Home") { Navigator.shared.requestedTool = .home }
                }
            } else if cloud.files?.isEmpty == true, cloud.hasMoreThanItRead {
                // The scan stopped early, so an empty list does not mean there is nothing to free.
                ContentUnavailableView {
                    Label("Nothing Found So Far", systemImage: "icloud")
                } description: {
                    VStack(spacing: 8) {
                        if cloud.cutShort != nil {
                            Text("There is more in iCloud Drive than Peel can read in the time it gives a scan, and nothing in the part it read is big enough to be worth freeing.")
                        }
                        if !whyPartlyRead.isEmpty {
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text(Self.partlyReadTitle)
                                InfoNote(about: Text(Self.partlyReadTitle), detail: partlyReadNote, isAlbum: false)
                            }
                        }
                        if !cloud.notRead.isEmpty {
                            UnreadableFoldersDetail(folders: cloud.notRead)
                        }
                        sharedDownloadsNote
                    }
                } actions: {
                    EmptyStateActions {
                        UnreadableFoldersActions(folders: cloud.notRead, needsFullDiskAccess: !whyPartlyRead.isEmpty)
                    }
                }
            } else if cloud.files?.isEmpty == true, cloud.isNotSetUp {
                ContentUnavailableView {
                    Label("iCloud Drive Isn’t Set Up", systemImage: "icloud.slash")
                } description: {
                    Text("This account doesn’t use iCloud Drive on this Mac, so there is nothing here to free.")
                }
            } else if cloud.files?.isEmpty == true {
                ContentUnavailableView {
                    Label("Nothing to Free", systemImage: "checkmark.seal")
                } description: {
                    VStack(spacing: 8) {
                        Text("Peel found no file here that is safely in iCloud and big enough to be worth freeing.")
                        sharedDownloadsNote
                    }
                }
            }
        }
        .edgeBar(.bottom) {
            if cloud.files?.isEmpty == false {
                RemovalBar(
                    selectedSize: cloud.selectedSize,
                    hasSelection: !cloud.selectedURLs.isEmpty,
                    isScanning: cloud.isScanning,
                    isWorking: cloud.isFreeing,
                    scan: cloud.scanRun,
                    isEnabled: cloud.selectedSize > 0 && !cloud.isFreeing,
                    onRemove: { isConfirming = true },
                    title: "Remove Downloads",
                    systemImage: "icloud.and.arrow.down",
                    notice: freed,
                    removal: (cloud.freeing, cloud.stopFreeing),
                    recordsInHistory: false
                )
            }
        }
        .fadesInColumn(whenRowsChange: cloud.files?.map(\.id))
        .announcesScan(
            cloud.isScanning,
            found: cloud.summary,
            couldNotLook: cloud.couldNotLook,
            wasStopped: cloud.scanRun.wasStopped
        )
        .navigationTitle(Text(Tool.cloud.title))
        .toolbar {
            ToolbarItem {
                RescanButton(isRunning: $isRescanning, isDisabled: cloud.freeing.isMoving, scan: cloud.scanRun) {
                    await cloud.refresh()
                }
            }
        }
        .confirmationDialog(Text("Remove the downloads from this Mac?"), isPresented: $isConfirming) {
            Button("Remove Downloads") {
                Task {
                    let bytes = await cloud.freeSelected()
                    if !cloud.refusals.isEmpty {
                        leftAlone = LeftAlone(freed: bytes, refusals: cloud.refusals)
                    }
                    guard bytes > 0 else { return }
                    freed = BarNotice(figure: bytes.byteCount, words: "Freed")
                    AccessibilityNotification.Announcement(AttributedString(localized: "Freed \(bytes.byteCount) on this Mac.")).post()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This frees \(cloud.selectedSize.byteCount). Nothing is deleted from iCloud: the files stay there, Finder still lists them, and they download again when you open them, which takes an internet connection.")
        }
        .alert(
            leftAlone?.freed == 0 ? Text("No downloads were removed.") : Text("Some downloads couldn’t be removed."),
            isPresented: Binding(get: { leftAlone != nil }, set: { if !$0 { leftAlone = nil } }),
            presenting: leftAlone
        ) { _ in
            Button("OK") {}
        } message: { leftAlone in
            Text(verbatim: leftAlone.message)
        }
        .task {
            guard cloud.files == nil, !cloud.scanRun.isWaitedFor, !cloud.scanRun.wasStopped else { return }
            await cloud.refresh()
        }
        .rescanOnExclusionChange("CloudView") { await cloud.refresh() }
        .onChange(of: searchText) { closedInSearch = [] }
        .task(id: freed) {
            guard freed != nil else { return }
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            freed = nil
        }
    }

    static let aboutCloud: LocalizedStringResource = "Files in iCloud that are also downloaded to this Mac. Remove Downloads takes away only the copy here; each file stays in iCloud and downloads again when you open it."
    static let onThisMacNote: LocalizedStringResource = "Finder still lists these files after their downloads are removed. Peel never deletes a file from iCloud."
    static let partlyReadTitle: LocalizedStringResource = "Peel did not read all of iCloud Drive"
    static let tooBigTitle: LocalizedStringResource = "iCloud Drive is too big to read in one scan"
    static let tooBigNote: LocalizedStringResource = "So this list is not all of it."

    /// Why the list may not hold all of iCloud Drive, a sentence for each reason, or none when Peel read all of it.
    static func whyPartlyRead(restNotRead: Bool, folders: [String]) -> [LocalizedStringResource] {
        var why: [LocalizedStringResource] = []
        if restNotRead {
            why.append("macOS kept Peel out of the rest, so this list may not be complete.")
        }
        if !folders.isEmpty {
            why.append("macOS kept Peel out of \(folders.formatted(.list(type: .and))), so this list may not be complete.")
        }
        return why
    }

    private var whyPartlyRead: [LocalizedStringResource] {
        Self.whyPartlyRead(restNotRead: cloud.readOnlyTheHomesFolders, folders: cloud.unreadableFolders)
    }

    /// The reasons, then, once Full Disk Access may have been given, that it takes reopening Peel.
    private var partlyReadNote: Text {
        let sentences = whyPartlyRead.map { String(localized: $0) }
            + (home.needsRelaunchForFullDiskAccess ? [HomeModel.reopenForFullDiskAccess] : [])
        return Text(verbatim: sentences.joined(separator: "\n\n"))
    }

    @ViewBuilder private var sharedDownloadsNote: some View {
        if cloud.sharedDownloads > 0 {
            Text(verbatim: Self.sharedDownloadsWords(cloud.sharedDownloads))
        }
    }

    static func sharedDownloadsWords(_ count: Int) -> String {
        String(inflecting: "Not listed: ^[\(count) download](inflect: true) sharing space with another copy. Removing one would free nothing.")
    }

    /// Whether the note column is on: while a listed download has a note, so the note is drawn beside it.
    static func hasNoteColumn(_ files: [CloudFile]) -> Bool {
        files.contains { $0.note != nil }
    }

    private func selectableRows(_ files: [CloudFile]) -> SelectableRows<URL> {
        SelectableRows(
            rows: files.map(\.url),
            selectable: files.map(\.url),
            recommended: files.filter(\.isRecommended).map(\.url)
        )
    }

    private func isOpen(_ folder: CloudFolder) -> Bool {
        searchText.isEmpty ? opened.contains(folder.url) : !closedInSearch.contains(folder.url)
    }

    private func toggle(_ folder: CloudFolder) {
        if searchText.isEmpty {
            opened.formSymmetricDifference([folder.url])
        } else {
            closedInSearch.formSymmetricDifference([folder.url])
        }
    }

    private func phase(listed: [CloudFile]) -> ScanPhase {
        if cloud.files == nil { return cloud.scanRun.wasStopped ? .stopped : .scanning(.walk) }
        if !searchText.isEmpty, cloud.files?.isEmpty == false, listed.isEmpty { return .message }
        if cloud.couldNotRead { return .message }
        if cloud.files?.isEmpty == true { return .message }
        return .content
    }

    private var header: some View {
        PageHeader(systemImage: "icloud") {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("iCloud Drive")
                    .pageTitle()
                InfoNote(about: Text("iCloud Drive"), detail: Text(Self.aboutCloud), isAlbum: false)
                    .beside(.title.bold())
            }
        } details: {
            EmptyView()
        } trailing: {
            if let total = cloud.total {
                TotalLabel(total: total, caption: Text("on this Mac"))
            }
        }
    }
}

/// The files one Remove Downloads left as they were, and what it freed.
private struct LeftAlone {
    let freed: Int64
    let refusals: [CloudRefusal]

    /// The first few files with the reason each stayed, as the alert after a removal lists them. Still Here, at the
    /// top of the page, lists them all.
    var message: String {
        RemovalFailureAlert.underTheirReasons(refusals.map { ($0.url.abbreviatedPath, $0.explanation) })
            .joined(separator: "\n\n")
    }
}

extension CloudFile {
    /// Why Peel doesn't recommend removing this download, said beside its row, or nil.
    var note: LocalizedStringResource? {
        isDesktopPicture
            ? "Not selected: it is the wallpaper, which macOS keeps open while it is shown, so its download can’t be removed now."
            : heldBack?.explanation
    }
}
