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
            if !search.selection.outside.isEmpty, !search.keepsWhatIsOutside {
                HStack(alignment: .firstTextBaseline) {
                    Label("Selected but not in this search: ^[\(search.selection.outside.count) file](inflect: true).", systemImage: "checklist")
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Button("Keep Selected") { search.keepWhatIsOutside() }
                        .buttonStyle(.borderless)
                    Button("Deselect") { search.deselectWhatIsOutside() }
                        .buttonStyle(.borderless)
                }
                .listRowSeparator(.hidden)
            }
            if let results = search.results, !results.files.isEmpty, !results.leftOut.isEmpty {
                Label {
                    LeftOutLines(leftOut: results.leftOut, alignment: .leading)
                } icon: {
                    Image(systemName: "eye.slash")
                }
                .foregroundStyle(.secondary)
                .listRowSeparator(.hidden)
            }
            if let results = search.results, !results.files.isEmpty {
                Section {
                    ForEach(results.files) { file in
                        // On macOS 27 the day the file was modified stands in the column other lists give the kind.
                        if #available(macOS 27, *) {
                            RemovalRow(
                                url: file.url,
                                icon: .file(file.url),
                                detail: nil,
                                kind: "\(file.modificationDate, format: .dateTime.day().month(.abbreviated).year())",
                                warning: warning(for: file),
                                size: file.size,
                                isLeftAlone: file.requiresPrivileges,
                                isFirst: file.id == results.files.first?.id,
                                isChoosable: true,
                                selection: search, isSelected: search.isSelected(file.url)
                            )
                            .tag(file.url)
                        } else {
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
        .accessibilityLabel(Text(Tool.fileSearch.title))
        .scrollBarBelowSectionHeaders(search.results?.files.isEmpty == false)
        .scanState(phase, isRescanning: search.isSearching, fadesInResults: false, scan: search.scanRun) {
            if search.results == nil {
                ContentUnavailableView(
                    "Search for Files",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Type a name, or choose a kind or size in Filters.")
                )
            } else if search.results?.didRun == false {
                ContentUnavailableView(
                    "Spotlight Didn’t Answer",
                    systemImage: "exclamationmark.magnifyingglass",
                    description: Text("Peel asked Spotlight and got no answer, so it can’t say what is on this Mac. Try the search again.")
                )
            } else if let results = search.results, results.files.isEmpty {
                let disks = results.unindexedDisks.formatted(.list(type: .and))
                if results.isNothingIndexed {
                    ContentUnavailableView(
                        "Not Indexed by Spotlight",
                        systemImage: "magnifyingglass",
                        description: Text("Spotlight isn’t indexing \(disks), so File Search can’t find anything there. A disk listed in System Settings > Spotlight > Search Privacy is left out until you remove it there.")
                    )
                } else if !results.leftOut.isEmpty {
                    ContentUnavailableView {
                        Label("All Results Left Out", systemImage: "eye.slash")
                    } description: {
                        VStack(spacing: 8) {
                            LeftOutLines(leftOut: results.leftOut)
                            if !results.unindexedDisks.isEmpty {
                                Text("Spotlight isn’t indexing \(disks), so File Search can’t find anything there.")
                            }
                        }
                    }
                } else {
                    // A search shows this only once it answered for the criteria as they are now.
                    let criteria = search.criteria
                    ContentUnavailableView {
                        Label("No Results", systemImage: "magnifyingglass")
                    } description: {
                        VStack(spacing: 8) {
                            if !criteria.trimmedName.isEmpty {
                                Text("Check the spelling or try a new search.")
                            }
                            if criteria.narrowingFilters > 0 {
                                Text("The filters you chose may leave out what you’re looking for.")
                            }
                            if results.unindexedDisks.isEmpty {
                                Text("File Search finds only what Spotlight indexes, so a folder listed in System Settings > Spotlight > Search Privacy isn’t searched.")
                            } else {
                                Text("Spotlight isn’t indexing \(disks), so File Search can’t find anything there.")
                            }
                            if criteria.scope == .computer {
                                Text("Network volumes aren’t searched.")
                            }
                        }
                    } actions: {
                        if criteria.narrowingFilters > 0 {
                            Button("Clear Filters") { search.criteria = criteria.clearingFilters() }
                        }
                    }
                }
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
            couldNotLook: message,
            wasStopped: search.scanRun.wasStopped || !search.criteria.isSearchable
        )
        // Here the column's search field is part of the search, so it is always shown.
        .columnSearch(text: $search.criteria.name, prompt: "Search Files", when: true)
        .navigationTitle(Text(Tool.fileSearch.title))
        .toolbar {
            ToolbarItem {
                let filters = search.criteria.narrowingFilters
                Button(
                    "Filters",
                    systemImage: filters > 0 ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle"
                ) { isShowingFilters = true }
                    .help(Text("Filters"))
                    .accessibilityValue(filters > 0 ? Text("^[\(filters) filter](inflect: true) on") : Text(verbatim: ""))
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
            file.belongsToAnApp
                ? String(localized: "An app keeps this in its Library folder, and may be using it right now.")
                : nil,
            file.heldBack.map { String(localized: $0.explanation) },
            file.freesLessThanItsLength
                ? String(localized: "Moving this frees less than its length of \(file.length.byteCount): another file shares its storage, or it takes less space than that.")
                : nil,
        ].compactMap(\.self)
        return lines.isEmpty ? nil : lines.joined(separator: "\n\n")
    }

    /// The title of the page's own message where it says more than that nothing was found.
    private var message: LocalizedStringResource? {
        guard let results = search.results else { return nil }
        if !results.didRun { return "Spotlight Didn’t Answer" }
        if results.isNothingIndexed { return "Not Indexed by Spotlight" }
        return results.files.isEmpty && !results.leftOut.isEmpty ? "All Results Left Out" : nil
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

private struct LeftOutLines: View {
    let leftOut: [FileSearch.LeftOut: Int]
    var alignment = HorizontalAlignment.center

    var body: some View {
        VStack(alignment: alignment, spacing: 6) {
            ForEach(FileSearch.LeftOut.allCases.filter { leftOut[$0] != nil }, id: \.self) { reason in
                line(for: reason, count: leftOut[reason] ?? 0)
            }
        }
    }

    private func line(for reason: FileSearch.LeftOut, count: Int) -> Text {
        switch reason {
        case .syncs:
            Text("Left out: ^[\(count) file](inflect: true) in iCloud or another place that syncs to your other devices. Peel never moves what syncs, since moving it to the Trash would also remove it from them.")
        case .excluded:
            Text("Left out: ^[\(count) file](inflect: true) among what you excluded in Settings.")
        case .exclusionsNotKnown:
            Text("Left out: ^[\(count) file](inflect: true), since Peel can’t check what it finds against your exclusions until it can read them.")
        case .protected:
            Text("Left out: ^[\(count) file](inflect: true) in places Peel never moves anything from, such as macOS itself, Mail, Messages, or a photo library.")
        case .couldNotBeRead:
            Text("Left out: ^[\(count) file](inflect: true) macOS didn’t let Peel look at.")
        }
    }
}
