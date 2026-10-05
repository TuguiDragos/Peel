import PeelCore
import SwiftUI

struct OrphanDetailView: View {
    @Environment(OrphanLibrary.self) private var orphans
    @Environment(HelperModel.self) private var helper
    let group: OrphanGroup

    var body: some View {
        List {
            header
                .listRowSeparator(.hidden)
            RemovalsHeldBanner()

            if orphans.scan?.needsFullDiskAccess == true {
                FullDiskAccessBanner()
            } else if let unreadable = orphans.scan?.unreadableLocations, !unreadable.isEmpty {
                UnreadableFoldersNotice(folders: unreadable.map(\.url))
            }
            if group.items.contains(where: { $0.requiresPrivileges && $0.leftAlone == nil }), !helper.canAct {
                HelperRequiredBanner()
            }

            Section {
                RemovalColumnHeaders(hasNoteColumn: hasNoteColumn)
                ForEach(Array(group.items.enumerated()), id: \.element.id) { index, item in
                    RemovalRow(
                        url: item.url,
                        icon: .symbol(item.kind.symbolName),
                        detail: item.modificationDate.map { "Modified \($0, format: .relative(presentation: .named))" },
                        kind: item.kind.title,
                        warning: warning(for: item),
                        size: item.size ?? 0,
                        isMeasured: item.size != nil,
                        isLocked: isLocked(item),
                        isLeftAlone: item.leftAlone != nil,
                        isFirst: index == 0,
                        hasNoteColumn: hasNoteColumn,
                        selection: orphans, isSelected: orphans.isSelected(item.url)
                    )
                }
                .listRowSeparator(.hidden)
            } header: {
                SectionHeaderLine {
                    Text("Files")
                } actions: {
                    SelectMenu(list: list, place: Text(verbatim: group.title), selection: orphans)
                }
            }
        }
        .dimmedWhileBusy(orphans.isScanning)
        .safeAreaBar(edge: .bottom) {
            RemovalBar(page: Tool.orphans.page(group.identifier), isScanning: orphans.isScanning, scan: orphans.scanRun)
        }
        .fadesInColumn(whenRowsChange: group.items.map(\.id))
        .navigationTitle(group.title)
        .toolbar(removing: .title)
    }

    private var hasNoteColumn: Bool {
        group.items.contains { $0.modificationDate != nil || warning(for: $0) != nil }
    }

    private func warning(for item: OrphanItem) -> String? {
        let lines = [
            item.heldBack.map { String(localized: $0.explanation) },
            item.holdsDamagedSettings
                ? String(localized: "Can’t be read as a property list, so nothing can read these settings.")
                : nil,
        ].compactMap(\.self)
        return lines.isEmpty ? nil : lines.joined(separator: "\n\n")
    }

    private var header: some View {
        PageHeader(systemImage: "questionmark.folder") {
            Text(verbatim: group.title)
                .pageTitle()
                .textSelection(.enabled)
                .help(Text(verbatim: group.title))
        } details: {
            if let badge = group.confidence.badge {
                Badge(title: badge, systemImage: group.confidence.systemImage, tint: group.confidence.tint)
            }
            if let remembered = group.rememberedApp {
                Text(verbatim: group.identifier)
                    .font(.subheadline.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                // Shown in full, so a long path never hides the date, which is what this line is for.
                Text("Peel last saw it at \((remembered.lastPath as NSString).abbreviatingWithTildeInPath) on \(remembered.lastSeen, format: .dateTime.day().month().year()).")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("No app installed on this Mac claims these files.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        } trailing: {
            TotalLabel(total: group.movable, caption: Text("to remove"))
                .accessibilityLabel(Text("\(group.movable.text) can be moved to the Trash"))
        }
    }

    /// Peel recommends no row it held back: such a row waits to be chosen by hand, as Review Before Removing does on
    /// an app's page.
    private var list: SelectableRows<URL> {
        SelectableRows(
            rows: group.items.map(\.url),
            selectable: group.items.filter { !isLocked($0) && $0.leftAlone == nil }.map(\.url),
            recommended: group.items.filter { !isLocked($0) && $0.heldBack == nil }.map(\.url)
        )
    }

    private func isLocked(_ item: OrphanItem) -> Bool {
        item.requiresPrivileges && !helper.canAct
    }
}
