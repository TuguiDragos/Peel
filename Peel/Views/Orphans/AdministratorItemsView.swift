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

            if let scan = orphans.scan, scan.needsFullDiskAccess || !scan.unreadableLocations.isEmpty {
                UnreadableFoldersNotice(
                    folders: scan.unreadableLocations.map(\.url),
                    needsFullDiskAccess: scan.needsFullDiskAccess
                )
            }

            Section {
                RemovalColumnHeaders(hasNoteColumn: true)
                ForEach(Array(items.enumerated()), id: \.element.id) { index, entry in
                    RemovalRow(
                        url: entry.item.url,
                        icon: .symbol(entry.item.kind.symbolName),
                        detail: entry.claim?.reason.title,
                        kind: entry.item.kind.title,
                        warning: warning(for: entry),
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

    private func warning(for entry: AdministratorItem) -> String {
        var lines = [String(localized: HoldBack.beyondTheHelper.explanation)]
        if entry.claim?.confidence == .possible {
            let apps = entry.apps.formatted(.list(type: .and))
            lines.append(String(localized: "Peel isn’t sure only \(apps) used this. Check it before you remove it."))
        }
        if entry.item.url.isKernelExtension {
            lines.append(String(localized: "macOS changes the kernel extensions it loads only when the Mac restarts, so restart once this one is in the Trash."))
        }
        return lines.joined(separator: "\n\n")
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
