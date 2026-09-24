import PeelCore
import SwiftUI

struct DuplicateList: View {
    @Environment(DuplicateLibrary.self) private var duplicates
    @Environment(HomeModel.self) private var home
    @Environment(ExclusionsStore.self) private var exclusions
    @State private var searchText = ""

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
                .columnSearch(text: $searchText, prompt: "Search Duplicates", when: !scan.groups.isEmpty || !scan.folderGroups.isEmpty)
                .overlay {
                    if !(scan.groups.isEmpty && scan.folderGroups.isEmpty), groups.isEmpty, folderGroups.isEmpty {
                        ContentUnavailableView.search(text: searchText)
                    } else if scan.readNothing {
                        // Shown instead of "No Duplicates": copies may be in folders Peel couldn't read or skipped.
                        ContentUnavailableView {
                            Label("Not Everything Could Be Read", systemImage: "exclamationmark.triangle")
                        } description: {
                            Text("No duplicates were found, but Peel couldn’t look in ^[\(scan.unreadableLocations.count + scan.skippedLocations.count) folder](inflect: true), so there may be some there. Give Peel Full Disk Access, or choose folders it can read.")
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
            } else {
                DuplicateScanForm()
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
                Button("New Scan", systemImage: "arrow.uturn.backward") {
                    duplicates.clearResults()
                }
                .disabled(duplicates.scan == nil || duplicates.isRemoving)
            }
        }
        .fadesInColumn(whenRowsChange: duplicates.scan.map { $0.groups.map(\.id) + $0.folderGroups.map(\.id) })
        .navigationTitle(Text(Tool.duplicates.title))
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
