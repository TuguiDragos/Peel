import PeelCore
import SwiftUI

struct OrphanList: View {
    @Environment(AppLibrary.self) private var library
    @Environment(OrphanLibrary.self) private var orphans
    @Environment(HelperModel.self) private var helper
    @State private var searchText = ""
    @State private var isRescanning = false

    var body: some View {
        @Bindable var orphans = orphans
        let filtered = filteredGroups
        let forAnAdministrator = filteredForAnAdministrator

        List(selection: $orphans.selection) {
            if !forAnAdministrator.isEmpty {
                AdministratorRow(items: forAnAdministrator)
                    .tag(OrphanPage.forAnAdministrator)
            }
            ForEach(filtered) { group in
                OrphanGroupRow(group: group)
                    .tag(OrphanPage.group(group.id))
            }
        }
        .accessibilityLabel(Text(Tool.orphans.title))
        .contextMenu(forSelectionType: OrphanPage.self) { pages in
            if pages.count == 1, case .group(let id)? = pages.first,
               let group = filtered.first(where: { $0.id == id }) {
                Menu("This Belongs To") {
                    // What a group belongs to is kept by the app's identifier.
                    let apps = library.apps.filter { $0.bundleIdentifier != nil }
                        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                    ForEach(apps) { app in
                        Button(app.name) { orphans.give(group, to: app) }
                    }
                }
            }
        }
        .scanState(phase(filtered, forAnAdministrator), isRescanning: isRescanning, scan: orphans.scanRun) {
            if !library.readEverything {
                ContentUnavailableView {
                    Label("Not Every App Could Be Read", systemImage: "exclamationmark.triangle")
                } description: {
                    let list = Text("Peel can’t read its list of app folders, so Orphaned Files lists nothing. Starting over keeps the old list beside a new one.")
                    let unread = Text("Peel couldn’t read \(RemovalFailureAlert.listedFolders(library.unreadable.map(\.abbreviatedPath))), so it can’t tell which apps are installed. Nothing is listed here, since the files of an app it can’t see would look orphaned.")
                    let access = Text("Give Peel Full Disk Access so it can read the folders macOS protects.")
                    let parts = (library.listOfFoldersUnreadable ? [list] : [])
                        + (library.unreadable.isEmpty ? [] : [unread])
                        + (library.unreadableNeedsFullDiskAccess ? [access] : [])
                    parts.dropFirst().reduce(parts.first ?? Text(verbatim: "")) { Text("\($0)\n\n\($1)") }
                } actions: {
                    if library.listOfFoldersUnreadable {
                        Button("Start Over") { library.startFoldersOver() }
                    }
                    UnreadableFoldersActions(
                        folders: library.unreadable,
                        needsFullDiskAccess: library.unreadableNeedsFullDiskAccess
                    )
                }
            } else if listsNothing, let unreadable = orphans.scan?.unreadableLocations, !unreadable.isEmpty {
                ContentUnavailableView {
                    Label("Not Everything Could Be Read", systemImage: "exclamationmark.triangle")
                } description: {
                    let named = Text("No orphaned files were found, but Peel couldn’t look inside \(RemovalFailureAlert.listedFolders(unreadable.map(\.url.abbreviatedPath))), so there may be some there.")
                    if orphans.scan?.needsFullDiskAccess == true {
                        Text("\(named)\n\n\(Text("Give Peel Full Disk Access so it can read the folders macOS protects."))")
                    } else {
                        named
                    }
                } actions: {
                    UnreadableFoldersActions(
                        folders: unreadable.map(\.url),
                        needsFullDiskAccess: orphans.scan?.needsFullDiskAccess == true
                    )
                }
            } else if listsNothing {
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
        .columnSearch(text: $searchText, prompt: "Search Orphaned Files", when: orphans.scan != nil && !listsNothing)
        .fadesInColumn(whenRowsChange: orphans.pages)
        .navigationTitle(Text(Tool.orphans.title))
        .announcesScan(
            orphans.isScanning,
            found: orphans.summary,
            couldNotLook: !library.readEverything ? "Not Every App Could Be Read"
                : orphans.scan?.unreadableLocations.isEmpty == false ? "Not Everything Could Be Read" : nil,
            wasStopped: orphans.scanRun.wasStopped
        )
        .toolbar {
            ToolbarItem {
                SelectOnEveryPage(
                    pages: SelectablePages(filtered.map { ($0.page, $0.selectableRows(canUseHelper: helper.canAct)) }),
                    selection: orphans
                ) { page in
                    // Needs an Administrator lists what can't move, so it has no bar either.
                    guard orphans.selection == nil || orphans.selection == .forAnAdministrator,
                          let group = filtered.first(where: { $0.page == page })
                    else { return }
                    orphans.selection = .group(group.id)
                }
            }
            ToolbarItem {
                RescanButton(
                    isRunning: $isRescanning,
                    isDisabled: !library.hasLoaded || orphans.isRemoving,
                    scan: orphans.scanRun
                ) {
                    // What could not be read may be readable now, so the apps are read again first.
                    if !library.readEverything {
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
        .rescanAfterPutBack(.orphans) { await orphans.refresh(from: library) }
    }

    private func phase(_ filtered: [OrphanGroup], _ forAnAdministrator: [AdministratorItem]) -> ScanPhase {
        if !library.readEverything { return .message }
        if orphans.scan == nil { return orphans.scanRun.wasStopped ? .stopped : .scanning(.walk) }
        if listsNothing { return .message }
        if filtered.isEmpty, forAnAdministrator.isEmpty, !searchText.isEmpty { return .message }
        return .content
    }

    /// True once a scan found nothing at all to list, before any search.
    private var listsNothing: Bool {
        orphans.scan.map { $0.groups.isEmpty && $0.forAnAdministrator.isEmpty } ?? false
    }

    private var filteredGroups: [OrphanGroup] {
        let groups = orphans.scan?.groups ?? []
        guard !searchText.isEmpty else { return groups }
        return groups.filter {
            SearchText.matches($0.identifier, searchText) || SearchText.matches($0.title, searchText)
        }
    }

    /// What only an administrator can move, all of it while the search names its row, and otherwise the items whose
    /// path or app the search names.
    private var filteredForAnAdministrator: [AdministratorItem] {
        let items = orphans.scan?.forAnAdministrator ?? []
        guard !searchText.isEmpty, !SearchText.matches(String(localized: AdministratorRow.title), searchText) else {
            return items
        }
        return items.filter { item in
            SearchText.matches(item.item.url.path(percentEncoded: false), searchText)
                || item.apps.contains { SearchText.matches($0, searchText) }
        }
    }
}

/// The row of what only an administrator can move, first in the list.
private struct AdministratorRow: View {
    static let title: LocalizedStringResource = "Needs an Administrator"
    let items: [AdministratorItem]

    var body: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Self.title)
                    .lineLimit(1)
                Text("Only an administrator can remove these")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 6)
            Text(SizeTotal(items.map(\.item.size)).text)
                .rowFigure()
        }
        .padding(.vertical, 2)
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
                Group {
                    if let tint = group.confidence.tint {
                        StatusLabel(
                            title: group.confidence.summary, systemImage: group.confidence.systemImage, tint: tint
                        )
                    } else {
                        group.confidence.summary
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 6)
            Text(group.movable.text)
                .rowFigure()
        }
        .padding(.vertical, 2)
    }
}
