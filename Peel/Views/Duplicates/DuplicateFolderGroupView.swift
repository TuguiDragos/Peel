import PeelCore
import SwiftUI

struct DuplicateFolderGroupView: View {
    @Environment(DuplicateLibrary.self) private var duplicates
    let group: DuplicateFolderGroup

    var body: some View {
        List {
            header
                .listRowSeparator(.hidden)
            RemovalsHeldBanner()

            Section {
                ForEach(Array(group.folders.enumerated()), id: \.element.id) { index, folder in
                    DuplicateFolderRow(
                        duplicates: duplicates,
                        folder: folder,
                        group: group,
                        isSelected: duplicates.isSelected(folder),
                        canChangeSelection: duplicates.canChange(folder, in: group),
                        isFirst: index == 0
                    )
                }
                .listRowSeparator(.hidden)
            } header: {
                heading("Copies", "A selected folder goes to the Trash with everything in it. Peel always keeps at least one, and it moves a folder only if nothing inside it has changed since the scan.")
            }
            .disabled(duplicates.isRemoving)
        }
        .edgeBar(.bottom) {
            DuplicateRemovalBar()
        }
        .fadesInColumn(whenRowsChange: group.folders.map(\.id))
        .navigationTitle(Text(verbatim: group.folders[0].url.lastPathComponent))
        .toolbar(removing: .title)
    }

    private var header: some View {
        HStack(spacing: 20) {
            copies
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: group.folders[0].url.lastPathComponent)
                    .pageTitle()
                    .help(Text(verbatim: group.folders[0].url.lastPathComponent))
                HStack(spacing: 6) {
                    Badge(title: Text(verbatim: group.size.byteCount), systemImage: "folder", tint: .secondary)
                    Badge(title: Text("^[\(group.fileCount) file](inflect: true)"), systemImage: "doc", tint: .secondary)
                    Badge(title: Text(group.folders.count, format: .number), systemImage: "folder.badge.plus", tint: .secondary)
                        .accessibilityLabel(Text("^[\(group.folders.count) copy](inflect: true)"))
                }
            }
            Spacer(minLength: 8)
            DuplicateSelectedTotal(bytes: duplicates.selectedSize(in: group))
        }
        .padding(.vertical, 8)
    }

    private var copies: some View {
        ZStack {
            ForEach(Array(group.folders.prefix(3).enumerated()).reversed(), id: \.offset) { index, folder in
                FileThumbnail(url: folder.url)
                    .frame(width: 62, height: 62)
                    .offset(x: [0, 8, -9][index], y: [0, -4, 5][index])
                    .zIndex(Double(3 - index))
            }
        }
        .frame(width: 92, height: 80)
        .accessibilityHidden(true)
    }
}

private struct DuplicateFolderRow: View {
    let duplicates: DuplicateLibrary
    let folder: DuplicateFolder
    let group: DuplicateFolderGroup
    let isSelected: Bool
    let canChangeSelection: Bool
    var isFirst = false

    var body: some View {
        HStack(spacing: 0) {
            Toggle(isOn: Binding(get: { isSelected }, set: { duplicates.setSelected($0, folder, in: group) })) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(Color.accentColor)
                        .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 3 }
                        .accessibilityHidden(true)
                    Text(folder.url.abbreviatedPath)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 12)
                    if !isSelected {
                        Badge(title: Text("Keep"), systemImage: "checkmark", tint: .green)
                    }
                    Text(folder.size.byteCount)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.checkbox)
            .disabled(!canChangeSelection)
            .help(canChangeSelection ? Text(verbatim: folder.url.path(percentEncoded: false)) : Text("Peel always keeps at least one copy."))
        }
        .tableRow(isFirst: isFirst)
        .contextMenu {
            ItemMenu(url: folder.url)
        }
    }
}
