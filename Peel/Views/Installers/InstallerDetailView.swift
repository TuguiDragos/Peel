import AppKit
import PeelCore
import SwiftUI

struct InstallerDetailView: View {
    static let deleteBackupNote: LocalizedStringResource = "What is inside came off a device and may be the only copy. Delete a backup in System Settings > General > Storage > iOS Files."

    @Environment(InstallerLibrary.self) private var installers
    @Environment(HelperModel.self) private var helper
    @Environment(SelectionCarrier.self) private var carrier
    let kind: InstallerItem.Kind

    var body: some View {
        let rows = items
        let hasNoteColumn = rows.contains {
            !$0.isReadOnly && (detail(for: $0) != nil || Self.warning(for: $0) != nil)
        }
        let showsDays = rows.contains { !$0.isReadOnly && $0.date != nil }
        let isOnlyToRead = Self.isOnlyToRead(rows, of: kind, canUseHelper: helper.canAct)

        List {
            header(rows)
                .listRowSeparator(.hidden)
            if kind != .deviceBackup {
                RemovalsHeldBanner()
            }

            let locked = rows.count { $0.isLocked(canUseHelper: helper.canAct) }
            if locked > 0 {
                HelperRequiredBanner(need: .moving(locked))
            }

            Section {
                ForEach(rows) { item in
                    if item.isReadOnly {
                        BackupRow(item: item, isFirst: item.id == rows.first?.id)
                    } else {
                        let shown = Self.shownPath(of: item.url, kind: kind)
                        RemovalRow(
                            url: item.url,
                            name: shown?.name,
                            folder: shown?.folder,
                            icon: .file(item.url),
                            detail: detail(for: item),
                            kind: Self.day(of: item, showsDays: showsDays),
                            warning: Self.warning(for: item),
                            size: item.size ?? 0,
                            isMeasured: item.size != nil,
                            isLocked: item.isLocked(canUseHelper: helper.canAct),
                            isLeftAlone: item.heldBack?.cannotBeMoved == true,
                            isFirst: item.id == rows.first?.id,
                            hasNoteColumn: hasNoteColumn,
                            isReadOnly: isOnlyToRead,
                            selection: installers, isSelected: installers.isSelected(item.url)
                        )
                    }
                }
                .listRowSeparator(.hidden)
            } header: {
                SectionHeaderLine {
                    heading(kind.title, kind.explanation)
                } count: {
                    // A list to read keeps the heading that says what these are, with how many and their size.
                    if isOnlyToRead {
                        Text("^[\(rows.count) item](inflect: true) · \(SizeTotal(rows.map(\.size)).text)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                } actions: {
                    if !isOnlyToRead {
                        SelectMenu(
                            list: rows.selectableRows(canUseHelper: helper.canAct),
                            place: Text(kind.title),
                            selection: installers
                        )
                    }
                }
            }

            if kind == .deviceBackup {
                Section {
                } header: {
                    HeadingWithActions {
                        heading("How to Delete a Backup", Self.deleteBackupNote)
                    } actions: {
                        Button("Open System Settings") {
                            NSWorkspace.shared.open(Installers.storageSettingsURL)
                        }
                    }
                }
            }
        }
        .scrollBarBelowSectionHeaders()
        .dimmedWhileBusy(installers.isScanning)
        .edgeBar(.bottom) {
            if kind != .deviceBackup,
               !rows.selectableRows(canUseHelper: helper.canAct).selectable.isEmpty
                || carrier.movesSomething(from: kind.page) {
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

    /// The name a row shows first and the folder under it: a firmware file's own, since firmware files share long
    /// folders and have names that differ in the middle, which a cut path hides.
    static func shownPath(of url: URL, kind: InstallerItem.Kind) -> (name: String, folder: String)? {
        guard kind == .firmware else { return nil }
        let folder = url.deletingLastPathComponent().fullPath as NSString
        return (url.lastPathComponent, folder.abbreviatingWithTildeInPath)
    }

    /// True when a kind other than device backups lists items and a click can select none of them: the page is then a
    /// list to read. Device backups are always one, with rows of their own.
    static func isOnlyToRead(_ rows: [InstallerItem], of kind: InstallerItem.Kind, canUseHelper: Bool) -> Bool {
        kind != .deviceBackup && !rows.isEmpty && rows.selectableRows(canUseHelper: canUseHelper).selectable.isEmpty
    }

    private var items: [InstallerItem] {
        installers.shownItems(in: kind)
    }

    private func header(_ rows: [InstallerItem]) -> some View {
        PageHeader(systemImage: kind.systemImage) {
            Text(kind.title)
                .pageHeading()
        } details: {
            FlowLayout {
                Badge(title: Text("^[\(rows.count) item](inflect: true)"), systemImage: "square.and.arrow.down")
                if kind == .deviceBackup {
                    Badge(title: Text("Listed only"), systemImage: "hand.raised")
                }
            }
        } trailing: {
            let total = rows.shownTotal(of: kind, canUseHelper: helper.canAct)
            if kind == .deviceBackup || !total.isNothing {
                TotalLabel(total: total, caption: Text(kind == .deviceBackup ? "on this Mac" : "to remove"))
            }
        }
    }

    /// What a row's note says with its detail: why the item is left for the person to choose, and why moving it frees
    /// less than its size.
    static func warning(for item: InstallerItem) -> String? {
        let lines = [
            item.heldBack.map { String(localized: $0.explanation(keptInStepBy: item.syncedBy, openBy: item.openBy)) },
            item.takesOnDisk.map {
                String(localized: "Moving this frees less than its size of \($0.byteCount): another file shares its storage, or it takes less room on disk than that.")
            },
        ].compactMap(\.self)
        return lines.isEmpty ? nil : lines.joined(separator: "\n\n")
    }

    /// The day in the column other lists give the kind: when the item came, or when it last changed. A row without
    /// one reads Unknown while others show theirs, so the whole table moves under the path at the same width.
    static func day(of item: InstallerItem, showsDays: Bool) -> LocalizedStringResource? {
        guard showsDays else { return nil }
        guard let date = item.date else { return "Unknown" }
        return "\(date, format: .dateTime.day().month(.abbreviated).year())"
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
        case .downloadedBy(let app): "An update \(app) downloaded"
        case .unusedByAnyVirtualMachine: "Not used by any virtual machine"
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
