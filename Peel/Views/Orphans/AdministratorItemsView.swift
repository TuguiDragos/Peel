import AppKit
import PeelCore
import SwiftUI

/// What only an administrator can move, from places Peel's helper may not move it from, and how to remove it by hand.
struct AdministratorItemsView: View {
    @Environment(OrphanLibrary.self) private var orphans
    let items: [AdministratorItem]

    var body: some View {
        List {
            header
                .listRowSeparator(.hidden)

            if orphans.scan?.needsFullDiskAccess == true {
                FullDiskAccessBanner()
            } else if let unreadable = orphans.scan?.unreadableLocations, !unreadable.isEmpty {
                UnreadableFoldersNotice(folders: unreadable.map(\.url))
            }

            Section {
                RemovalColumnHeaders(hasNoteColumn: true)
                ForEach(Array(items.enumerated()), id: \.element.id) { index, entry in
                    RemovalRow(
                        url: entry.item.url,
                        icon: .symbol(entry.item.kind.symbolName),
                        detail: nil,
                        kind: entry.item.kind.title,
                        warning: String(localized: HoldBack.beyondTheHelper.explanation),
                        lastWritten: entry.item.modificationDate,
                        foundFor: entry.apps.formatted(.list(type: .and)),
                        size: entry.item.size ?? 0,
                        isMeasured: entry.item.size != nil,
                        isLeftAlone: true,
                        isFirst: index == 0,
                        selection: orphans, isSelected: false
                    )
                }
                .listRowSeparator(.hidden)
            } header: {
                SectionHeaderLine {
                    Text("Files")
                } actions: {
                    EmptyView()
                }
            }
        }
        .scrollBarBelowSectionHeaders()
        .dimmedWhileBusy(orphans.isScanning)
        .fadesInColumn(whenRowsChange: items.map(\.id))
        .navigationTitle(Text("Needs an Administrator"))
        .toolbar(removing: .title)
    }

    private var header: some View {
        PageHeader(systemImage: "lock.shield") {
            Text("Needs an Administrator")
                .pageHeading()
        } details: {
            Text("Only an administrator can move these, and Peel’s helper isn’t allowed to move them from where they are. To remove one, show it in Finder, drag it to the Trash, then enter an administrator name and password when macOS asks.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Show in Finder", systemImage: "folder") {
                NSWorkspace.shared.activateFileViewerSelecting(items.map(\.item.url))
            }
        }
    }
}
