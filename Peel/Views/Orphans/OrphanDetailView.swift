import PeelCore
import SwiftUI

struct OrphanDetailView: View {
    @Environment(AppLibrary.self) private var library
    @Environment(OrphanLibrary.self) private var orphans
    @Environment(HelperModel.self) private var helper
    @Environment(RemovalHistoryStore.self) private var history
    @State private var isConfirmingRemoval = false
    @Environment(RemovalOutcome.self) private var outcome
    let group: OrphanGroup

    var body: some View {
        List {
            header
                .listRowSeparator(.hidden)
            ExclusionsUnreadableBanner()

            if orphans.scan?.unreadableLocations.isEmpty == false {
                FullDiskAccessBanner()
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
                        warning: item.leftAlone.map { String(localized: $0.explanation) },
                        size: item.size ?? 0,
                        isMeasured: item.size != nil,
                        isLocked: item.requiresPrivileges && !helper.canAct,
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
                    SelectAllButton(selectable: selectableURLs, selection: Bindable(orphans).selectedURLs)
                }
            }
        }
        .dimmedWhileBusy(orphans.isScanning)
        .safeAreaBar(edge: .bottom) {
            RemovalBar(
                selectedSize: selected.known,
                isSelectionMeasured: selected.isComplete,
                isScanning: orphans.isScanning,
                scan: orphans.scanRun,
                isEnabled: !orphans.selected(in: group).isEmpty && !orphans.isRemoving && !orphans.isScanning,
                onRemove: { isConfirmingRemoval = true }
            )
        }
        .fadesInColumn(whenRowsChange: group.items.map(\.id))
        .navigationTitle(group.title)
        .toolbar(removing: .title)
        // The dialog counts only this group's selected items, because items selected in other groups are not moved.
        .confirmationDialog(Text.movingToTrash(orphans.selected(in: group).count, selected), isPresented: $isConfirmingRemoval) {
            Button("Move to Trash") {
                Task { await remove() }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var hasNoteColumn: Bool {
        group.items.contains { $0.modificationDate != nil || $0.leftAlone != nil }
    }

    /// The total size that can be moved to the Trash. Items Peel leaves alone are listed but not counted, as
    /// on an app's page.
    private var movable: SizeTotal {
        SizeTotal(group.items.filter { $0.leftAlone == nil }.map(\.size))
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
            TotalLabel(total: movable, caption: Text("to remove"))
                .accessibilityLabel(Text("\(movable.text) can be moved to the Trash"))
        }
    }

    private var selected: SizeTotal {
        SizeTotal(orphans.selected(in: group).map(\.size))
    }

    private var selectableURLs: [URL] {
        group.items.filter { $0.leftAlone == nil && (helper.canAct || !$0.requiresPrivileges) }.map(\.url)
    }

    private func remove() async {
        let result = await orphans.removeSelected(in: group, installedApps: library.apps)
        outcome.report(result)
        // History is written before the rescan, which can take a while: it is how the user puts back what just moved.
        await history.record(result, tool: .orphans, source: group.identifier, sizes: [URL: Int64](measured: group.items.map { ($0.url, $0.size) }))
        await orphans.refresh(from: library)
    }
}
