import PeelCore
import SwiftUI

struct DuplicateList: View {
    @Environment(DuplicateLibrary.self) private var duplicates
    @Environment(ExclusionsStore.self) private var exclusions
    @Environment(\.openSettings) private var openSettings
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
                let local = groups.filter { !$0.everyCopySyncs }
                // The groups whose every copy syncs to other devices, which Peel shows and never moves, in a
                // section of their own, so they never mix with what is on this Mac.
                let synced = groups.filter(\.everyCopySyncs)
                // Headings appear only when folder groups or synced groups are listed. A list of files alone has none.
                List(selection: $duplicates.selection) {
                    if !folderGroups.isEmpty || !synced.isEmpty {
                        if !folderGroups.isEmpty {
                            Section {
                                folderRows(folderGroups)
                            } header: {
                                Text("Folders")
                            }
                        }
                        if !local.isEmpty {
                            Section {
                                fileRows(local)
                            } header: {
                                Text("Files")
                            }
                        }
                        if !synced.isEmpty {
                            Section {
                                fileRows(synced)
                            } header: {
                                Text("Synced to Other Devices")
                            }
                        }
                    } else {
                        fileRows(local)
                    }
                }
                .accessibilityLabel(Text(Tool.duplicates.title))
                .scrollBarBelowSectionHeaders(!folderGroups.isEmpty || !synced.isEmpty)
                .columnSearch(text: $searchText, prompt: "Search Duplicates", when: !scan.groups.isEmpty || !scan.folderGroups.isEmpty)
                .overlay {
                    if !(scan.groups.isEmpty && scan.folderGroups.isEmpty), groups.isEmpty, folderGroups.isEmpty {
                        ContentUnavailableView.search(text: searchText)
                    } else if scan.exclusionsNotKnown {
                        ContentUnavailableView {
                            Label("Peel couldn’t read your exclusions", systemImage: "exclamationmark.triangle")
                        } description: {
                            Text("Peel compares nothing until you start the list over in Settings, since it would read what you asked it to leave alone.")
                        } actions: {
                            Button("Open Peel Settings") { SettingsPane.exclusions.open(with: openSettings) }
                        }
                    } else if scan.readNothing {
                        // Shown instead of "No Duplicates": copies may be in folders Peel couldn't read, which are
                        // named, or in the chosen folders it set aside, each named with why.
                        ContentUnavailableView {
                            if scan.unreadableLocations.isEmpty {
                                Label("Not Everything Could Be Searched", systemImage: "exclamationmark.triangle")
                            } else {
                                Label("Not Everything Could Be Read", systemImage: "exclamationmark.triangle")
                            }
                        } description: {
                            if scan.needsFullDiskAccess || !scan.unreadableLocations.isEmpty {
                                Text(verbatim: UnreadableFoldersNotice.detail(
                                    naming: scan.unreadableLocations.map(\.abbreviatedPath),
                                    needsFullDiskAccess: scan.needsFullDiskAccess
                                ))
                            }
                            if !scan.skippedLocations.isEmpty {
                                Text(verbatim: Self.reasons(scan.skippedLocations))
                            }
                        } actions: {
                            UnreadableFoldersActions(
                                folders: scan.unreadableLocations,
                                needsFullDiskAccess: scan.needsFullDiskAccess
                            )
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
            } else if duplicates.wasStopped {
                StoppedScan()
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
                selectMenu
            }
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
            couldNotLook: duplicates.scan?.exclusionsNotKnown == true ? "Peel couldn’t read your exclusions"
                : duplicates.scan?.readNothing != true ? nil
                : duplicates.scan?.unreadableLocations.isEmpty == true ? "Not Everything Could Be Searched"
                : "Not Everything Could Be Read",
            wasStopped: duplicates.scan == nil
        )
        .navigationTitle(Text(Tool.duplicates.title))
    }

    /// What VoiceOver hears when a scan ends: what it found, then the folders Peel couldn't read and the chosen
    /// folders it set aside, each kind in its own words.
    private var summary: AttributedString? {
        guard let scan = duplicates.scan else { return duplicates.summary }
        let found = duplicates.summary ?? (scan.groups.isEmpty && scan.folderGroups.isEmpty
            ? nil : AttributedString(localized: "Nothing to move: every other copy syncs to your other devices."))
        guard var words = found else { return nil }
        if !scan.unreadableLocations.isEmpty {
            let count = scan.unreadableLocations.count
            words = words + " " + AttributedString(localized: "Peel couldn’t look in ^[\(count) folder](inflect: true).")
        }
        if !scan.skippedLocations.isEmpty {
            words = words + " " + AttributedString(localized: "Some folders couldn’t be searched.")
        }
        return words
    }

    /// Each folder set aside and why, as many as an alert lists.
    static func reasons(_ folders: [DuplicateScan.FolderSetAside]) -> String {
        RemovalFailureAlert.firstItems(folders.map { "\($0.url.abbreviatedPath)\n\($0.reason.explanation)" })
            .joined(separator: "\n\n")
    }

    /// Select Recommended and Deselect All over the groups the list shows. There is no Select All: one copy of every
    /// group always stays.
    private var selectMenu: some View {
        let scan = duplicates.scan
        let groups = scan?.groups.filter { $0.matches(searchText) } ?? []
        let folderGroups = scan?.folderGroups.filter { $0.matches(searchText) } ?? []
        let selected = (files: duplicates.selectedURLs, folders: duplicates.selectedFolders)
        let recommended = scan?.selectingRecommended(
            in: groups, folderGroups, files: selected.files, folders: selected.folders
        )
        let none = scan?.deselecting(groups, folderGroups, files: selected.files, folders: selected.folders)
        return Menu {
            Button("Select Recommended") { duplicates.selectRecommended(in: groups, folderGroups) }
                .disabled(recommended.map { $0 == selected } ?? true)
            Button("Deselect All") { duplicates.deselectAll(in: groups, folderGroups) }
                .disabled(none.map { $0 == selected } ?? true)
        } label: {
            ToolbarMenuLabel(title: "Select", systemImage: "checklist")
        }
        .disabled(groups.isEmpty && folderGroups.isEmpty || duplicates.isRemoving)
        .help(Text("Select on every page in the list"))
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
            if group.everyCopySyncs {
                // Nothing here frees space on this Mac: the figure is the copies' size, with the symbol that says
                // they sync, the cloud only when every copy syncs through one.
                Label {
                    Text(group.size.byteCount)
                } icon: {
                    let throughACloud = group.files.allSatisfy(\.syncsThroughACloud)
                    Image(systemName: DuplicateFile.syncSymbol(throughACloud: throughACloud))
                }
                .rowFigure()
            } else {
                Text(group.reclaimableSize.byteCount)
                    .rowFigure()
            }
        }
        .padding(.vertical, 2)
    }
}
