import PeelCore
import PeelLink
import SwiftUI

struct AppList: View {
    @Environment(AppLibrary.self) private var library
    @Environment(HomebrewLibrary.self) private var homebrew
    @Environment(ExclusionsStore.self) private var exclusions
    @State private var isRescanning = false
    let searchText: String

    var body: some View {
        @Bindable var library = library
        let visible = library.visibleApps(matching: searchText)
        let excluded = library.excludedIDs(by: exclusions.exclusions)
        let row = { (app: InstalledApp) in self.row(for: app, isExcluded: excluded.contains(app.id)) }

        List(selection: $library.selection) {
            if let problem = library.teamRecordProblem {
                TeamRecordNotice(problem: problem)
            }
            if visible.waiting.isEmpty {
                ForEach(visible.rest, content: row)
            } else {
                Section {
                    ForEach(visible.waiting, content: row)
                } header: {
                    Text("Updates Available")
                }
                if !visible.rest.isEmpty {
                    Section {
                        ForEach(visible.rest, content: row)
                    } header: {
                        Text("Everything Else")
                    }
                }
            }
        }
        .overlay {
            if library.isLoading, library.apps.isEmpty {
                ProgressView()
            } else if visible.isEmpty, !library.apps.isEmpty, !searchText.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else if visible.isEmpty, !library.apps.isEmpty {
                ContentUnavailableView(
                    "No Apps Match",
                    systemImage: "line.3.horizontal.decrease.circle",
                    description: Text("Change the filters to see more apps.")
                )
            } else if library.hasLoaded, library.apps.isEmpty {
                ContentUnavailableView(
                    "No Apps Found",
                    systemImage: "app.dashed",
                    description: Text("Peel found no apps in the Applications folders, which on a Mac in use means it couldn’t read them.")
                )
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            let applicationURLs = urls.compactMap(OpenRequest.applicationURL(from:))
            guard !applicationURLs.isEmpty else { return false }
            Task { await library.reveal(applicationURLs) }
            return true
        }
        .fadesInColumn(whenRowsChange: library.apps.map(\.id))
        .navigationTitle(Text(Tool.applications.title))
        .announcesScan(library.isLoading, found: library.summary)
        .toolbar {
            ToolbarItem {
                ExportMenu()
            }
            ToolbarItem {
                AppListMenu()
            }
            ToolbarItem {
                // The folder watcher reads the apps on its own; this is for someone who has just installed one.
                RescanButton(isRunning: $isRescanning, isDisabled: library.isLoading, scan: library.scanRun) {
                    let changed = await library.refresh()
                    guard !changed.isEmpty else { return }
                    await library.checkForUpdates(changed, force: true)
                    await library.checkSigningTeams()
                }
            }
        }
        .dimmedWhileBusy(isRescanning)
        .task(id: library.revision) {
            await library.loadSizes()
        }
        .task(id: homebrew.revision) {
            library.loadHomebrewCasks(homebrew.caskEvidence, knowsItsOwnApps: homebrew.knowsItsOwnApps)
        }
    }

    private func row(for app: InstalledApp, isExcluded: Bool) -> some View {
        AppRow(
            library: library,
            app: app,
            updateStatus: library.updateStatuses[app.id],
            size: library.sizes[app.id],
            isUnmeasured: library.unmeasured.contains(app.id),
            teamChange: library.teamChanges[app.bundleIdentifier],
            sort: library.sort,
            hasUpdate: library.hasUpdate(app),
            isPicked: library.picked.contains(app.id),
            isExcluded: isExcluded
        )
        .tag(app.id)
        .contextMenu {
            ItemMenu(url: app.url, appIdentifier: app.bundleIdentifier, isExcluded: isExcluded)
        }
    }
}

/// Says that Peel is not keeping its record of who signs each app, so no change of signer is being reported.
private struct TeamRecordNotice: View {
    @Environment(AppLibrary.self) private var library
    let problem: TeamRegistry.Problem

    var body: some View {
        Group {
            switch problem {
            case .unreadable:
                Notice(
                    title: Text("Peel can’t read its record of who signs your apps"),
                    detail: Text("Until you start the record over, Peel can’t warn you when an app’s signer changes. Starting over keeps the old file beside a new one.")
                ) {
                    Button("Start Over") {
                        Task { await library.startTeamRecordOver() }
                    }
                }
            case .unsaved:
                Notice(
                    title: Text("Peel couldn’t save its record of who signs your apps"),
                    detail: Text("Until it can, Peel may not warn you when an app’s signer changes.")
                ) { EmptyView() }
            }
        }
        .padding(.vertical, 6)
        .listRowSeparator(.hidden)
    }
}

/// Writes out what is installed and where each app came from.
private struct ExportMenu: View {
    @Environment(AppLibrary.self) private var library
    @Environment(HomebrewLibrary.self) private var homebrew
    @State private var failure: String?

    var body: some View {
        Menu {
            // The whole menu waits for Homebrew's list, because without it every cask app's source would read
            // "Unknown".
            ForEach(Inventory.Format.offered(by: homebrew), id: \.self) { format in
                Button(String(localized: format.title)) {
                    Task { failure = await InventoryExport.run(format: format, apps: library.apps, homebrew: homebrew) }
                }
            }
        } label: {
            ToolbarMenuLabel(title: "Export List of Apps", systemImage: "doc.badge.arrow.up")
        }
        .disabled(!library.hasLoaded || (homebrew.isInstalled && homebrew.packages == nil))
        .help(Text("Save a list of what is installed and where it came from"))
        .alert("The list couldn’t be saved.", isPresented: isShowingFailure) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(verbatim: failure ?? "")
        }
    }

    private var isShowingFailure: Binding<Bool> {
        Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })
    }
}

private struct AppListMenu: View {
    @Environment(AppLibrary.self) private var library

    var body: some View {
        Menu {
            AppListMenuContent(library: library)
        } label: {
            ToolbarMenuLabel(title: "Sort and Filter", systemImage: library.isFiltering ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
    }
}

/// How the Applications list is sorted and filtered, shared by its toolbar menu and View > Sort and Filter.
struct AppListMenuContent: View {
    @Bindable var library: AppLibrary

    var body: some View {
        Picker("Sort By", selection: $library.sort) {
            ForEach(AppSort.allCases) { sort in
                Text(sort.title).tag(sort)
            }
        }
        .pickerStyle(.inline)

        Section("Source") {
            ForEach(AppSource.allCases) { source in
                Toggle(String(localized: source.title), isOn: Binding(
                    get: { library.sources.contains(source) },
                    set: { isOn in
                        if isOn {
                            library.sources.insert(source)
                        } else {
                            library.sources.remove(source)
                        }
                    }
                ))
            }
        }

        let developers = library.developers
        if !developers.isEmpty {
            Picker(selection: $library.selectedDeveloper) {
                Text("All Developers").tag(String?.none)
                ForEach(developers, id: \.self) { developer in
                    Text(verbatim: developer).tag(String?.some(developer))
                }
            } label: {
                Text(LocalizedStringResource("Developer (maker)", defaultValue: "Developer", comment: "Who makes an app, as a filter of the app list; not the Developer tool."))
            }
            .pickerStyle(.menu)
        }

        Section {
            Toggle("Not Opened in \(AppLibrary.unusedMonths) Months", isOn: $library.showsOnlyUnused)
        }
    }
}

private struct AppRow: View {
    /// The size's minimum width, so the marks in front of it line up from row to row. 56 points fits the widest
    /// size the list prints, such as "245,5 MB", and a wider one still shows in full rather than cut.
    private static let sizeColumn: CGFloat = 56

    /// Only written to, by the checkbox: everything the row draws is passed in. Observation tracks a whole
    /// stored property, not one key, so a row that read `library.sizes[app.id]` would be redrawn every time any
    /// app's size arrived.
    let library: AppLibrary
    let app: InstalledApp
    let updateStatus: UpdateStatus?
    let size: Int64?
    /// True when the bundle could not be measured, so the size reads "Unknown" rather than staying blank as it does
    /// while it is measured.
    let isUnmeasured: Bool
    let teamChange: TeamRegistry.Change?
    let sort: AppSort
    let hasUpdate: Bool
    let isPicked: Bool
    let isExcluded: Bool

    var body: some View {
        HStack(spacing: 10) {
            NativeCheckbox(isOn: pick, label: app.name, help: String(localized: "Select this app to remove it with others"))
            AppIcon(url: app.url)
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 1) {
                // The checkbox beside it already says the name.
                Text(app.name)
                    .lineLimit(1)
                    .accessibilityHidden(true)
                captionLine
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if let change = teamChange {
                let words = change.current.isEmpty ? Text("No developer signs it anymore") : Text("Signed by someone else now")
                Image(systemName: "exclamationmark.shield.fill")
                    .rowTint(.orange)
                    .help(words)
                    .accessibilityLabel(words)
            }
            if isExcluded {
                Image(systemName: "hand.raised.fill")
                    .foregroundStyle(.secondary)
                    .help(Text(.excludedApp))
                    .accessibilityLabel(Text(.excludedApp))
            }
            // Always drawn, even before the sizes arrive, so nothing shifts when they do.
            Text(size?.byteCount ?? (isUnmeasured ? String(localized: "Unknown") : ""))
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(minWidth: Self.sizeColumn, alignment: .trailing)
        }
        .padding(.vertical, 2)
    }

    /// The versions this row sits between, when it is waiting for an update.
    private var update: (installed: String?, latest: String)? {
        guard hasUpdate, let latest = updateStatus?.displayVersion else { return nil }
        return (app.version, latest)
    }

    /// An app waiting for an update says which version it would go to, the way the Homebrew list does. The
    /// section heading already says an update is waiting, so the version is the part worth reading.
    ///
    /// Some versions are long, so the pair "installed → latest" shows only where it fits. Otherwise the latest
    /// version shows alone, cut at the end if need be, keeping its start, where the most significant part is.
    @ViewBuilder
    private var captionLine: some View {
        if let update {
            if let installed = update.installed {
                ViewThatFits(in: .horizontal) {
                    Text(verbatim: "\(installed) → \(update.latest)").monospacedDigit()
                    Text(verbatim: update.latest).monospacedDigit()
                }
                // The arrow is drawn, not spoken.
                .accessibilityLabel(Text("Update available: \(update.latest)"))
            } else {
                Text("Update to \(update.latest)")
            }
        } else {
            caption
        }
    }

    /// Every other row says when it was last opened, or when it arrived if that is what the list is sorted by.
    private var caption: Text {
        switch sort {
        case .lastOpened, .name, .size:
            if let lastUsedDate = app.lastUsedDate {
                Text("Opened \(lastUsedDate, format: .relative(presentation: .named))")
            } else if let version = app.version {
                Text(verbatim: version)
            } else {
                Text("Never opened")
            }
        case .dateAdded:
            if let dateAdded = app.dateAdded {
                Text("Added \(dateAdded, format: .relative(presentation: .named))")
            } else {
                Text(verbatim: app.version ?? "")
            }
        }
    }

    /// Adds the app to the batch or removes it, and clears the chosen row so the page shows the batch again.
    private var pick: Binding<Bool> {
        Binding(
            get: { isPicked },
            set: { isPicked in
                if isPicked {
                    library.picked.insert(app.id)
                } else {
                    library.picked.remove(app.id)
                }
                library.selection = []
            }
        )
    }
}
