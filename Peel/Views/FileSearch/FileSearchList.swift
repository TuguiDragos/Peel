import PeelCore
import SwiftUI

/// The files a search found, with every state of the search, in the list column as every tool keeps its items.
struct FileSearchList: View {
    @Environment(FileSearchLibrary.self) private var search
    @Environment(ExclusionsStore.self) private var exclusions
    @Environment(RemovalHistoryStore.self) private var history
    @State private var isConfirmingRemoval = false
    @State private var isShowingFilters = false
    @State private var isRescanning = false
    @Environment(RemovalOutcome.self) private var outcome

    var body: some View {
        @Bindable var search = search

        List(selection: $search.chosen) {
            ExclusionsUnreadableBanner()
            // Says the limit rather than counting the rows, since exclusions added after the search take files
            // out of the list, and can empty it, while the rest stays unlisted.
            if search.results?.isTruncated == true {
                Label("Peel lists at most ^[\(FileSearch.maximumResults) file](inflect: true), yours first and largest first. Narrow the search to see the rest.", systemImage: "exclamationmark.magnifyingglass")
                    .foregroundStyle(.secondary)
                    .listRowSeparator(.hidden)
            }
            if let results = search.results, !results.files.isEmpty {
                Section {
                    ForEach(results.files) { file in
                        RemovalRow(
                            url: file.url,
                            icon: .file(file.url),
                            detail: "Modified \(file.modificationDate, format: .relative(presentation: .named))",
                            warning: file.belongsToAnApp
                                ? String(localized: "An app keeps this in its Library folder, and may be using it right now.")
                                : nil,
                            size: file.size,
                            isLocked: file.requiresPrivileges,
                            isFirst: file.id == results.files.first?.id,
                            isChoosable: true,
                            selection: search, isSelected: search.isSelected(file.url)
                        )
                        .tag(file.url)
                    }
                    .listRowSeparator(.hidden)
                } header: {
                    SectionHeaderLine {
                        Text("Files")
                    } actions: {
                        SelectAllButton(selectable: Array(search.selectableURLs), selection: Bindable(search).selectedURLs)
                    }
                }
                // Disables the section, not the list, so the list still scrolls and the user can review the selection.
                .disabled(search.isSearching || search.isRemoving)
            }
        }
        .scanState(phase, isRescanning: search.isSearching, scan: search.scanRun) {
            if search.results == nil {
                ContentUnavailableView(
                    "Search for Files",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Type a name or choose a kind or size.")
                )
            } else if search.results?.didRun == false {
                ContentUnavailableView(
                    "Spotlight Didn’t Answer",
                    systemImage: "exclamationmark.magnifyingglass",
                    description: Text("Peel asked Spotlight and got no answer, so it can’t say what is on this Mac. Check that Spotlight indexing is on.")
                )
            } else if search.results?.files.isEmpty == true {
                ContentUnavailableView.search
            }
        }
        .safeAreaBar(edge: .bottom) {
            if search.results?.files.isEmpty == false {
                RemovalBar(
                    selectedSize: search.selectedSize,
                    isScanning: search.isSearching,
                    isEnabled: !search.selectedURLs.isEmpty && !search.isRemoving && !search.isSearching,
                    onRemove: { isConfirmingRemoval = true }
                )
            }
        }
        .fadesInColumn(whenRowsChange: search.results?.files.map(\.id))
        // Clearing the words stops the search too.
        .announcesScan(
            search.isSearching,
            found: search.summary,
            couldNotLook: search.results?.didRun == false ? "Spotlight Didn’t Answer" : nil,
            wasStopped: search.scanRun.wasStopped || !search.criteria.isSearchable
        )
        // The name is typed in the search field at the top of the column, where other pages filter their lists.
        // Here the field is part of the search, so it is always shown.
        .columnSearch(text: $search.criteria.name, prompt: "Search Files", when: true)
        .navigationTitle(Text(Tool.fileSearch.title))
        .toolbar {
            ToolbarItem {
                Button("Filters", systemImage: "line.3.horizontal.decrease.circle") { isShowingFilters = true }
                    .help(Text("Filters"))
                    .popover(isPresented: $isShowingFilters, arrowEdge: .bottom) {
                        FileSearchForm()
                    }
            }
            ToolbarItem {
                RescanButton(
                    isRunning: $isRescanning,
                    isDisabled: !search.criteria.isSearchable || search.isRemoving,
                    scan: search.scanRun
                ) {
                    await search.search()
                }
            }
        }
        .task(id: search.criteria) {
            guard search.criteria != search.searchedCriteria else { return }
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await search.search()
        }
        .task(id: exclusions.revision) {
            await search.leaveOut(exclusions.exclusions)
        }
        .confirmationDialog(
            Text.movingToTrash(search.selectedURLs.count, SizeTotal(known: search.selectedSize, isComplete: true)),
            isPresented: $isConfirmingRemoval
        ) {
            Button("Move to Trash") {
                Task {
                    let files = search.results?.files ?? []
                    let result = await search.removeSelected { result in
                        await history.record(
                            result,
                            tool: .fileSearch,
                            source: Tool.fileSearch.title.inEnglish,
                            sourceKey: "tool",
                            sizes: Dictionary(files.map { ($0.url, $0.size) }, uniquingKeysWith: { first, _ in first })
                        )
                    }
                    outcome.report(result)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var phase: ScanPhase {
        if search.isSearching, search.results?.files.isEmpty ?? true { return .scanning(.spotlight) }
        // A first search stopped before it answered says so; one left behind by words since cleared does not.
        if search.results == nil, search.scanRun.wasStopped, search.criteria.isSearchable { return .stopped }
        if search.results == nil { return .message }
        if search.results?.files.isEmpty == true { return .message }
        return .content
    }
}
