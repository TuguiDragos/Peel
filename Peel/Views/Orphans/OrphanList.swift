import PeelCore
import SwiftUI

struct OrphanList: View {
    @Environment(AppLibrary.self) private var library
    @Environment(OrphanLibrary.self) private var orphans
    @Environment(HomeModel.self) private var home
    @State private var searchText = ""
    @State private var isRescanning = false

    var body: some View {
        @Bindable var orphans = orphans
        let filtered = filteredGroups

        List(filtered, selection: $orphans.selection) { group in
            OrphanGroupRow(group: group)
        }
        .contextMenu(forSelectionType: OrphanGroup.ID.self) { ids in
            if ids.count == 1, let group = filtered.first(where: { ids.contains($0.id) }) {
                Menu("This Belongs To") {
                    let apps = library.apps.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                    ForEach(apps) { app in
                        Button(app.name) { orphans.give(group, to: app) }
                    }
                }
            }
        }
        .scanState(phase(filtered), isRescanning: isRescanning, scan: orphans.scanRun) {
            if orphans.scan?.groups.isEmpty == true, let unreadable = orphans.scan?.unreadableLocations, !unreadable.isEmpty {
                ContentUnavailableView {
                    Label("Not Everything Could Be Read", systemImage: "exclamationmark.triangle")
                } description: {
                    Text("No orphaned files were found, but Peel couldn’t look in ^[\(unreadable.count) folder](inflect: true), so there may be some there. Give Peel Full Disk Access to look there too.")
                } actions: {
                    Button("Open System Settings") { home.openFullDiskAccessSettings() }
                }
            } else if orphans.scan?.groups.isEmpty == true {
                ContentUnavailableView(
                    "No Orphaned Files",
                    systemImage: "checkmark.seal",
                    description: Text("Files named with an app’s identifier that no installed app claims will appear here.")
                )
            } else {
                ContentUnavailableView.search(text: searchText)
            }
        }
        .columnSearch(text: $searchText, prompt: "Search Orphaned Files", when: orphans.scan?.groups.isEmpty == false)
        .fadesInColumn(whenRowsChange: orphans.scan?.groups.map(\.id))
        .navigationTitle(Text(Tool.orphans.title))
        .announcesScan(
            orphans.isScanning,
            found: orphans.summary,
            couldNotLook: orphans.scan?.unreadableLocations.isEmpty == false ? "Not Everything Could Be Read" : nil,
            wasStopped: orphans.scanRun.wasStopped
        )
        .toolbar {
            ToolbarItem {
                RescanButton(isRunning: $isRescanning, isDisabled: !library.hasLoaded || orphans.isRemoving, scan: orphans.scanRun) {
                    await orphans.refresh(from: library)
                }
            }
        }
        // Scans again whenever the installed apps change, since a list made before an app was installed would
        // call that app's files orphaned. It never restarts a first scan the user stopped.
        .task(id: library.revision) {
            guard library.hasLoaded, orphans.scannedRevision != library.revision, !(orphans.scan == nil && orphans.scanRun.wasStopped) else { return }
            await orphans.refresh(from: library)
        }
        .rescanOnExclusionChange("OrphanList") { await orphans.refresh(from: library) }
    }

    private func phase(_ filtered: [OrphanGroup]) -> ScanPhase {
        if orphans.scan == nil { return orphans.scanRun.wasStopped ? .stopped : .scanning(.walk) }
        if orphans.scan?.groups.isEmpty == true { return .message }
        if filtered.isEmpty, !searchText.isEmpty { return .message }
        return .content
    }

    private var filteredGroups: [OrphanGroup] {
        let groups = orphans.scan?.groups ?? []
        guard !searchText.isEmpty else { return groups }
        return groups.filter { SearchText.matches($0.identifier, searchText) || SearchText.matches($0.title, searchText) }
    }
}

private struct OrphanGroupRow: View {
    let group: OrphanGroup

    var body: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: group.title)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if group.rememberedApp != nil {
                    Text(verbatim: group.identifier)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                // Shows why Peel thinks nothing uses these files, not a date the user would have to interpret. It is
                // shown whole, since the app's name can come last.
                group.confidence.summary
                    .font(.caption)
                    .rowTint(group.confidence.tint)
            }
            Spacer(minLength: 6)
            Text(group.movable.text)
                .rowFigure()
        }
        .padding(.vertical, 2)
    }
}
