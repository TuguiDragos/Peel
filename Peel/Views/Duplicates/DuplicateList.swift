import PeelCore
import SwiftUI

struct DuplicateList: View {
    @Environment(DuplicateLibrary.self) private var duplicates
    @Environment(HomeModel.self) private var home
    @Environment(ExclusionsStore.self) private var exclusions
    @State private var searchText = ""
    @State private var isConfirmingNewScan = false
    @State private var isShowingSettings = false
    @State private var isStartingScan = false

    var body: some View {
        @Bindable var duplicates = duplicates

        Group {
            if let scan = duplicates.scan {
                let folderGroups = scan.folderGroups.filter { $0.matches(searchText) }
                let groups = scan.groups.filter { $0.matches(searchText) }
                // Headings appear only when folder groups are listed. A list of files alone has none.
                List(selection: $duplicates.selection) {
                    if !folderGroups.isEmpty {
                        Section {
                            folderRows(folderGroups)
                        } header: {
                            Text("Folders")
                        }
                        if !groups.isEmpty {
                            Section {
                                fileRows(groups)
                            } header: {
                                Text("Files")
                            }
                        }
                    } else {
                        fileRows(groups)
                    }
                }
                .scrollBarBelowSectionHeaders()
                .columnSearch(text: $searchText, prompt: "Search Duplicates", when: !scan.groups.isEmpty || !scan.folderGroups.isEmpty)
                .overlay {
                    if !(scan.groups.isEmpty && scan.folderGroups.isEmpty), groups.isEmpty, folderGroups.isEmpty {
                        ContentUnavailableView.search(text: searchText)
                    } else if scan.readNothing {
                        // Shown instead of "No Duplicates": copies may be in folders Peel couldn't read or skipped.
                        ContentUnavailableView {
                            Label("Not Everything Could Be Read", systemImage: "exclamationmark.triangle")
                        } description: {
                            Text("No duplicates were found, but Peel couldn’t look in ^[\(scan.notLookedIn.count) folder](inflect: true), so there may be some there. Give Peel Full Disk Access, or choose folders it can read.")
                        } actions: {
                            if scan.needsFullDiskAccess {
                                Button("Open System Settings") { home.openFullDiskAccessSettings() }
                            }
                        }
                    } else if scan.groups.isEmpty, scan.folderGroups.isEmpty {
                        ContentUnavailableView(
                            "No Duplicates",
                            systemImage: "checkmark.seal",
                            description: Text("No folders or files with identical contents were found.")
                        )
                    }
                }
            } else if duplicates.isScanning {
                DuplicateScanProgressView()
                    .centeredOnColumn()
            } else {
                ContentUnavailableView {
                    Label("Find Duplicate Files", systemImage: "doc.on.doc")
                } description: {
                    Text("Choose folders and scan. Peel compares contents, so only exact copies are found, folders included.")
                } actions: {
                    Button("Scan Settings") { isShowingSettings = true }
                }
                .centeredOnColumn()
            }
        }
        .fadesInColumn(on: duplicates.scan == nil)
        .task(id: exclusions.revision) {
            await duplicates.leaveOut(exclusions.exclusions)
        }
        // Attached outside the `if`, so the column has a toolbar item before a scan as well. Without one, the
        // column gets no title bar section of its own, and the dividers between columns stop below the title bar.
        .toolbar {
            ToolbarItem {
                Button("Scan Settings", systemImage: "slider.horizontal.3") { isShowingSettings = true }
                    .help(Text("Scan Settings"))
                    .popover(isPresented: $isShowingSettings, arrowEdge: .bottom) {
                        DuplicateScanForm {
                            isShowingSettings = false
                            requestScan()
                        }
                    }
            }
            ToolbarItem {
                RescanButton(
                    isRunning: $isStartingScan,
                    isDisabled: !duplicates.canScan,
                    title: "Scan",
                    scan: duplicates
                ) {
                    requestScan()
                }
            }
        }
        .confirmationDialog("Start a new scan?", isPresented: $isConfirmingNewScan) {
            Button("New Scan") { duplicates.startScan() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The list of duplicates and your selection are cleared. No files are moved.")
        }
        .fadesInColumn(whenRowsChange: duplicates.scan.map { $0.groups.map(\.id) + $0.folderGroups.map(\.id) })
        // A scan ends without a result only when it was stopped.
        .announcesScan(
            duplicates.isScanning,
            found: summary,
            couldNotLook: duplicates.scan?.readNothing == true ? "Not Everything Could Be Read" : nil,
            wasStopped: duplicates.scan == nil
        )
        .navigationTitle(Text(Tool.duplicates.title))
    }

    /// What VoiceOver hears when a scan ends: what it found, and the folders it could not look in.
    private var summary: AttributedString? {
        guard let found = duplicates.summary, let count = duplicates.scan?.notLookedIn.count, count > 0 else {
            return duplicates.summary
        }
        return found + " " + AttributedString(localized: "Peel couldn’t look in ^[\(count) folder](inflect: true).")
    }

    /// A new scan clears what the last one found, so it asks first when there is something to lose.
    private func requestScan() {
        if let scan = duplicates.scan, !scan.groups.isEmpty || !scan.folderGroups.isEmpty {
            isConfirmingNewScan = true
        } else {
            duplicates.startScan()
        }
    }

    private func folderRows(_ groups: [DuplicateFolderGroup]) -> some View {
        ForEach(groups) { group in
            DuplicateFolderGroupRow(group: group)
                .tag(DuplicateRow.folder(group.id))
        }
    }

    private func fileRows(_ groups: [DuplicateGroup]) -> some View {
        ForEach(groups) { group in
            DuplicateGroupRow(group: group)
                .tag(DuplicateRow.file(group.id))
        }
    }
}

private struct DuplicateFolderGroupRow: View {
    let group: DuplicateFolderGroup

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder.fill")
                .font(.system(size: 20))
                .rowTint(Color.accentColor)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: group.folders[0].url.lastPathComponent)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 8) {
                    Label {
                        Text(group.folders.count, format: .number)
                    } icon: {
                        Image(systemName: "folder.badge.plus")
                    }
                    .accessibilityLabel(Text("^[\(group.folders.count) copy](inflect: true)"))
                    Text("^[\(group.fileCount) file](inflect: true)")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 6)
            Text(group.reclaimableSize.byteCount)
                .rowFigure()
        }
        .padding(.vertical, 2)
    }
}

private struct DuplicateGroupRow: View {
    let group: DuplicateGroup

    var body: some View {
        HStack(spacing: 10) {
            AppIcon(url: group.files[0].url)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: group.files[0].url.lastPathComponent)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 8) {
                    Label {
                        Text(group.files.count, format: .number)
                    } icon: {
                        Image(systemName: "doc.on.doc")
                    }
                    // The symbol is what says the number counts copies.
                    .accessibilityLabel(Text("^[\(group.files.count) copy](inflect: true)"))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 6)
            Text(group.reclaimableSize.byteCount)
                .rowFigure()
        }
        .padding(.vertical, 2)
    }
}
