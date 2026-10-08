import PeelCore
import SwiftUI

/// The files a search found, and every state of the search, in the list column.
struct FileSearchList: View {
    @Environment(FileSearchLibrary.self) private var search
    @Environment(ExclusionsStore.self) private var exclusions
    @State private var isShowingFilters = false
    @State private var isRescanning = false

    var body: some View {
        @Bindable var search = search

        List(selection: $search.chosen) {
            RemovalsHeldBanner()
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
                            warning: warning(for: file),
                            size: file.size,
                            isLeftAlone: file.requiresPrivileges,
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
                        SelectMenu(
                            list: SelectableRows(
                                rows: results.files.map(\.url),
                                selectable: results.files.filter { !$0.requiresPrivileges }.map(\.url),
                                recommended: results.files.map(\.url).filter(search.recommendedURLs.contains)
                            ),
                            place: Text(Tool.fileSearch.title),
                            selection: search
                        )
                    }
                }
                // Disables the section, not the list, so the list still scrolls and the user can review the selection.
                .disabled(search.isSearching || search.isRemoving)
            }
        }
        .scrollBarBelowSectionHeaders(search.results?.files.isEmpty == false)
        .scanState(phase, isRescanning: search.isSearching, fadesInResults: false, scan: search.scanRun) {
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
        .edgeBar(.bottom) {
            if search.results?.files.isEmpty == false {
                RemovalBar(page: Tool.fileSearch.page(), isScanning: search.isSearching)
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
        // Here the column's search field is part of the search, so it is always shown.
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
    }

    private func warning(for file: FoundFile) -> String? {
        let lines = [
            file.requiresPrivileges
                ? String(localized: "File Search moves only what your account can move. Use Finder for this one.")
                : nil,
            file.isInTheCloud
                ? String(localized: "This file is in iCloud Drive, so moving it to the Trash removes it from iCloud and from your other devices.")
                : file.belongsToAnApp
                ? String(localized: "An app keeps this in its Library folder, and may be using it right now.")
                : nil,
        ].compactMap(\.self)
        return lines.isEmpty ? nil : lines.joined(separator: "\n\n")
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
