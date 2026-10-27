import PeelCore
import SwiftUI

struct InstallerList: View {
    @Environment(AppLibrary.self) private var library
    @Environment(InstallerLibrary.self) private var installers
    @Environment(HelperModel.self) private var helper
    @State private var isRescanning = false
    @State private var searchText = ""

    /// The kinds to list. During a search, a kind is kept when its title or any of its items matches.
    private var listed: [InstallerItem.Kind] {
        guard !searchText.isEmpty else { return installers.sections }
        return installers.sections.filter { kind in
            SearchText.matches(String(localized: kind.title), searchText)
                || installers.items(in: kind).contains { $0.matches(searchText) }
        }
    }

    var body: some View {
        @Bindable var installers = installers
        let filtered = listed

        List(selection: $installers.selection) {
            if installers.needsFullDiskAccess {
                UnreadableFoldersNotice(folders: installers.unreadable, needsFullDiskAccess: true)
            }
            ForEach(filtered, id: \.self) { kind in
                let items = installers.items(in: kind)
                SectionRow(kind: kind, count: items.count, size: SizeTotal(items.map(\.size)))
                .tag(kind)
            }
        }
        .accessibilityLabel(Text(Tool.installers.title))
        .columnSearch(text: $searchText, prompt: "Search Installers and Backups", when: !installers.sections.isEmpty)
        .scanState(phase(filtered), isRescanning: isRescanning, scan: installers.scanRun) {
            if installers.sections.isEmpty, installers.needsFullDiskAccess {
                ContentUnavailableView {
                    Label("Not Everything Could Be Read", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(verbatim: UnreadableFoldersNotice.detail(
                        naming: installers.unreadable.map(\.abbreviatedPath),
                        needsFullDiskAccess: true
                    ))
                } actions: {
                    UnreadableFoldersActions(folders: installers.unreadable, needsFullDiskAccess: true)
                }
            } else if installers.sections.isEmpty {
                ContentUnavailableView(
                    "Nothing Left Over",
                    systemImage: "checkmark.seal",
                    description: Text("Peel found no installers, device firmware, unfinished downloads, or downloaded updates of \(Installers.minimumSize.byteCount) or more, and no iPhone or iPad backups.")
                )
            } else if filtered.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
        .fadesInColumn(whenRowsChange: installers.scan?.items.map(\.id))
        .navigationTitle(Text(Tool.installers.title))
        .announcesScan(
            installers.isScanning,
            found: installers.summary,
            couldNotLook: installers.sections.isEmpty && installers.needsFullDiskAccess
                ? "Not Everything Could Be Read" : nil,
            wasStopped: installers.scanRun.wasStopped
        )
        .toolbar {
            ToolbarItem {
                SelectOnEveryPage(
                    pages: SelectablePages(filtered.map { kind in
                        (kind.page, installers.items(in: kind).selectableRows(canUseHelper: helper.canAct))
                    }),
                    selection: installers
                ) { page in
                    guard installers.selection == nil, let kind = filtered.first(where: { $0.page == page }) else {
                        return
                    }
                    installers.selection = kind
                }
            }
            ToolbarItem {
                RescanButton(
                    isRunning: $isRescanning,
                    isDisabled: !library.hasLoaded || installers.isRemoving,
                    scan: installers.scanRun
                ) {
                    await installers.refresh(installedApps: library.apps)
                }
            }
        }
        .task(id: library.hasLoaded) {
            guard library.hasLoaded, installers.scan == nil, !installers.scanRun.isWaitedFor,
                  !installers.scanRun.wasStopped
            else { return }
            await installers.refresh(installedApps: library.apps)
        }
        .rescanOnExclusionChange("InstallerList") { await installers.refresh(installedApps: library.apps) }
        .rescanAfterPutBack(.installers) { await installers.refresh(installedApps: library.apps) }
    }

    private func phase(_ filtered: [InstallerItem.Kind]) -> ScanPhase {
        if installers.scan == nil { return installers.scanRun.wasStopped ? .stopped : .scanning(.walk) }
        if installers.sections.isEmpty { return .message }
        if !installers.sections.isEmpty, filtered.isEmpty { return .message }
        return .content
    }
}

private struct SectionRow: View {
    let kind: InstallerItem.Kind
    let count: Int
    let size: SizeTotal

    var body: some View {
        ToolRow(systemImage: kind.systemImage) {
            Text(kind.title)
                .lineLimit(2)
        } details: {
            Text("^[\(count) item](inflect: true)")
        } trailing: {
            Text(size.text)
                .rowFigure()
        }
    }
}
