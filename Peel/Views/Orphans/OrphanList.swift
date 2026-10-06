import PeelCore
import SwiftUI

struct OrphanList: View {
    @Environment(AppLibrary.self) private var library
    @Environment(OrphanLibrary.self) private var orphans
    @Environment(HelperModel.self) private var helper
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
            if !library.unreadable.isEmpty {
                ContentUnavailableView {
                    Label("Not Every App Could Be Read", systemImage: "exclamationmark.triangle")
                } description: {
                    let unread = Text("Peel couldn’t read \(library.unreadable.map(\.abbreviatedPath).formatted(.list(type: .and))), so it can’t tell which apps are installed. Nothing is listed here, since the files of an app it can’t see would look orphaned.")
                    if library.unreadableNeedsFullDiskAccess {
                        let access = Text("Give Peel Full Disk Access so it can read the folders macOS protects.")
                        Text("\(unread)\n\n\(access)")
                    } else {
                        unread
                    }
                } actions: {
                    if library.unreadableNeedsFullDiskAccess {
                        Button("Open System Settings") { home.openFullDiskAccessSettings() }
                    }
                }
            } else if orphans.scan?.groups.isEmpty == true, let unreadable = orphans.scan?.unreadableLocations,
               !unreadable.isEmpty {
                ContentUnavailableView {
                    Label("Not Everything Could Be Read", systemImage: "exclamationmark.triangle")
                } description: {
                    if orphans.scan?.needsFullDiskAccess == true {
                        Text("No orphaned files were found, but Peel couldn’t look in ^[\(unreadable.count) folder](inflect: true), so there may be some there. Give Peel Full Disk Access to look there too.")
                    } else {
                        Text("No orphaned files were found, but Peel couldn’t look inside \(unreadable.map(\.url.abbreviatedPath).formatted(.list(type: .and))), so there may be some there.")
                    }
                } actions: {
                    if orphans.scan?.needsFullDiskAccess == true {
                        Button("Open System Settings") { home.openFullDiskAccessSettings() }
                    }
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
        .edgeBar(.bottom) {
            Group {
                if let cutShort = orphans.scan?.cutShortLocations, !cutShort.isEmpty {
                    Text("There are more folders in \(cutShort.map(\.url.abbreviatedPath).formatted(.list(type: .and))) than Peel looks inside, so an orphaned file may be in a folder Peel didn’t reach.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                        .transition(.opacity)
                }
            }
            .motion(.settle, .movement, value: orphans.scan?.cutShortLocations.isEmpty == false)
        }
        .columnSearch(text: $searchText, prompt: "Search Orphaned Files", when: orphans.scan?.groups.isEmpty == false)
        .fadesInColumn(whenRowsChange: orphans.scan?.groups.map(\.id))
        .navigationTitle(Text(Tool.orphans.title))
        .announcesScan(
            orphans.isScanning,
            found: orphans.summary,
            couldNotLook: !library.unreadable.isEmpty ? "Not Every App Could Be Read"
                : orphans.scan?.unreadableLocations.isEmpty == false ? "Not Everything Could Be Read" : nil,
            wasStopped: orphans.scanRun.wasStopped
        )
        .toolbar {
            ToolbarItem {
                SelectOnEveryPage(
                    pages: SelectablePages(filtered.map { ($0.page, $0.selectableRows(canUseHelper: helper.canAct)) }),
                    selection: orphans
                )
            }
            ToolbarItem {
                RescanButton(
                    isRunning: $isRescanning,
                    isDisabled: !library.hasLoaded || orphans.isRemoving,
                    scan: orphans.scanRun
                ) {
                    // What could not be read may be readable now, so the apps are read again first.
                    if !library.unreadable.isEmpty {
                        await library.checkAgain(await library.refresh())
                    }
                    await orphans.refresh(from: library)
                }
            }
        }
        // Scans again whenever the installed apps change, or what could not be read of them, since a list made before
        // an app was installed would call that app's files orphaned. It never restarts a first scan the user stopped.
        .task(id: library.listing) {
            guard library.hasLoaded, orphans.scannedAgainst != library.listing,
                  !(orphans.scan == nil && orphans.scanRun.wasStopped)
            else { return }
            await orphans.refresh(from: library)
        }
        .rescanOnExclusionChange("OrphanList") { await orphans.refresh(from: library) }
    }

    private func phase(_ filtered: [OrphanGroup]) -> ScanPhase {
        if !library.unreadable.isEmpty { return .message }
        if orphans.scan == nil { return orphans.scanRun.wasStopped ? .stopped : .scanning(.walk) }
        if orphans.scan?.groups.isEmpty == true { return .message }
        if filtered.isEmpty, !searchText.isEmpty { return .message }
        return .content
    }

    private var filteredGroups: [OrphanGroup] {
        let groups = orphans.scan?.groups ?? []
        guard !searchText.isEmpty else { return groups }
        return groups.filter {
            SearchText.matches($0.identifier, searchText) || SearchText.matches($0.title, searchText)
        }
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
