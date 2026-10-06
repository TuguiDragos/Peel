import AppKit
import PeelCore
import SwiftUI

struct InstallerDetailView: View {
    @Environment(InstallerLibrary.self) private var installers
    @Environment(HelperModel.self) private var helper
    let kind: InstallerItem.Kind

    var body: some View {
        let rows = items
        let hasNoteColumn = rows.contains { !$0.isReadOnly && (detail(for: $0) != nil || $0.heldBack != nil) }

        List {
            header(rows)
                .listRowSeparator(.hidden)
            RemovalsHeldBanner()

            if rows.contains(where: { $0.isLocked(canUseHelper: helper.canAct) }) {
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
                            warning: item.heldBack.map { String(localized: $0.explanation) },
                            size: item.size ?? 0,
                            isMeasured: item.size != nil,
                            isLocked: item.isLocked(canUseHelper: helper.canAct),
                            isLeftAlone: item.heldBack?.cannotBeMoved == true,
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
                    SelectMenu(
                        list: rows.selectableRows(canUseHelper: helper.canAct),
                        place: Text(kind.title),
                        selection: installers
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
        .edgeBar(.bottom) {
            if kind != .deviceBackup {
                RemovalBar(
                    page: kind.page,
                    isScanning: installers.isScanning,
                    scan: installers.scanRun
                )
            }
        }
        .fadesInColumn(whenRowsChange: items.map(\.id))
        .navigationTitle(Text(kind.title))
        .toolbar(removing: .title)
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
                    Badge(title: Text("Read only"), systemImage: "hand.raised")
                }
            }
        } trailing: {
            TotalLabel(
                total: SizeTotal(rows.map(\.size)),
                caption: Text(kind == .deviceBackup ? "on this Mac" : "to remove")
            )
        }
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
                .accessibilityHidden(true)
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
        .accessibilityElement(children: .combine)
        .tableRow(isFirst: isFirst)
        .contextMenu {
            Button("Show in Finder", systemImage: "folder") {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            }
        }
    }
}
