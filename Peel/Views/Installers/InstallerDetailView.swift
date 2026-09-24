import AppKit
import PeelCore
import SwiftUI

struct InstallerDetailView: View {
    @Environment(AppLibrary.self) private var library
    @Environment(InstallerLibrary.self) private var installers
    @Environment(RemovalHistoryStore.self) private var history
    @State private var isConfirmingRemoval = false
    @Environment(RemovalOutcome.self) private var outcome
    @Environment(HelperModel.self) private var helper
    let kind: InstallerItem.Kind

    var body: some View {
        let rows = items
        let hasNoteColumn = rows.contains { !$0.isReadOnly && detail(for: $0) != nil }
        let selectedRows = selectedItems(among: rows)
        let selected = SizeTotal(selectedRows.map(\.size))

        List {
            header(rows)
                .listRowSeparator(.hidden)
            ExclusionsUnreadableBanner()

            if rows.contains(where: \.requiresPrivileges), !helper.canAct {
                HelperRequiredBanner()
            }

            Section {
                ForEach(rows) { item in
                    if item.isReadOnly {
                        BackupRow(item: item, isFirst: item.id == rows.first?.id)
                    } else {
                        RemovalRow(
                            url: item.url,
                            icon: .file(item.url),
                            detail: detail(for: item),
                            size: item.size ?? 0,
                            isMeasured: item.size != nil,
                            isLocked: item.requiresPrivileges && !helper.canAct,
                            isFirst: item.id == rows.first?.id,
                            hasNoteColumn: hasNoteColumn,
                            selection: installers, isSelected: installers.isSelected(item.url)
                        )
                    }
                }
                .listRowSeparator(.hidden)
            } header: {
                SectionHeaderLine {
                    heading(kind.title, kind.explanation)
                } actions: {
                    SelectAllButton(
                        selectable: rows.filter { !$0.isReadOnly && !($0.requiresPrivileges && !helper.canAct) }.map(\.url),
                        selection: Bindable(installers).selectedURLs
                    )
                }
            }

            if kind == .deviceBackup {
                Section {
                } header: {
                    HStack(spacing: 8) {
                        heading(
                            "Device Backups",
                            "In Finder, select a connected device, then General > Manage Backups: that is where a backup is removed. Peel doesn’t touch them: what is inside came off a device and may be the only copy."
                        )
                        Spacer(minLength: 8)
                        Button {
                            NSWorkspace.shared.open(URL(filePath: NSHomeDirectory()))
                        } label: {
                            Text("Open Finder")
                                .minimumTarget()
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
        .dimmedWhileBusy(installers.isScanning)
        .safeAreaBar(edge: .bottom) {
            if kind != .deviceBackup {
                RemovalBar(
                    selectedSize: selected.known,
                    isSelectionMeasured: selected.isComplete,
                    isScanning: installers.isScanning,
                    scan: installers.scanRun,
                    isEnabled: !selectedRows.isEmpty && !installers.isRemoving && !installers.isScanning,
                    onRemove: { isConfirmingRemoval = true }
                )
            }
        }
        .fadesInColumn(whenRowsChange: items.map(\.id))
        .navigationTitle(Text(kind.title))
        .toolbar(removing: .title)
        .confirmationDialog(Text.movingToTrash(selectedRows.count, selected), isPresented: $isConfirmingRemoval) {
            Button("Move to Trash") {
                Task {
                    // Sizes are read before the move: the rescan after it does not list the items that moved.
                    let sizes = Dictionary(items.map { ($0.url, $0.size ?? 0) }, uniquingKeysWith: { first, _ in first })
                    let result = await installers.removeSelected(in: kind, installedApps: library.apps) { result in
                        await history.record(result, tool: .installers, source: kind.title.inEnglish, sourceKey: "installers.\(kind.rawValue)", sizes: sizes)
                    }
                    outcome.report(result)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var items: [InstallerItem] {
        installers.items(in: kind)
    }

    private func header(_ rows: [InstallerItem]) -> some View {
        PageHeader(systemImage: kind.systemImage) {
            Text(kind.title)
                .pageHeading()
        } details: {
            FlowLayout {
                Badge(title: Text("^[\(rows.count) item](inflect: true)"), systemImage: "square.and.arrow.down")
                if kind == .deviceBackup {
                    NoteBadge(
                        title: Text("Read only"), systemImage: "hand.raised", tint: .secondary,
                        name: String(localized: "Read only"),
                        detail: Text("In Finder, select a connected device, then General > Manage Backups: that is where a backup is removed. Peel doesn’t touch them: what is inside came off a device and may be the only copy.")
                    )
                }
            }
        } trailing: {
            TotalLabel(
                total: SizeTotal(rows.map(\.size)),
                caption: Text(kind == .deviceBackup ? "on this Mac" : "to remove")
            )
        }
    }

    private func selectedItems(among rows: [InstallerItem]) -> [InstallerItem] {
        rows.filter { !$0.isReadOnly && installers.selectedURLs.contains($0.url) }
    }

    private func detail(for item: InstallerItem) -> LocalizedStringResource? {
        if let app = item.installedApp {
            return "\(app) is already installed"
        }
        return item.notes.first.map(\.words)
    }
}

extension InstallerItem.Note {
    var words: LocalizedStringResource {
        switch self {
        case .version(let version): "Version \(version)"
        case .name(let name): "\(name)"
        case .encrypted: "Encrypted"
        }
    }
}

/// A row for a device backup. It has no checkbox: Peel never removes a backup, because it may be the only copy
/// of a device's data.
private struct BackupRow: View {
    let item: InstallerItem
    let isFirst: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "iphone.gen3")
                .foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: item.name)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    ForEach(item.notes, id: \.self) { note in
                        Text(note.words)
                    }
                    if let date = item.date {
                        Text(date, format: .dateTime.day().month().year())
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            Text(item.size.byteCount)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .tableRow(isFirst: isFirst)
        .contextMenu {
            Button("Show in Finder", systemImage: "folder") {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            }
        }
    }
}
