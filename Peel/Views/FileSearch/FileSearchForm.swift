import PeelCore
import SwiftUI

struct FileSearchForm: View {
    private static let sizes: [Int64] = [10_000_000, 100_000_000, 500_000_000, 1_000_000_000, 5_000_000_000]

    @Environment(FileSearchLibrary.self) private var search
    @State private var isRescanning = false

    var body: some View {
        @Bindable var search = search

        Form {
            Section {
                Picker("Kind", selection: $search.criteria.kind) {
                    ForEach(FileKind.allCases, id: \.self) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                Picker("Size", selection: $search.criteria.minimumSize) {
                    Text("Any size").tag(Int64(0))
                    ForEach(Self.sizes, id: \.self) { size in
                        Text("At least \(size.byteCount)").tag(size)
                    }
                }
                Picker("Modified", selection: $search.criteria.unmodifiedDays) {
                    Text("Any time").tag(0)
                    Text("Over a month ago").tag(30)
                    Text("Over 3 months ago").tag(90)
                    Text("Over 6 months ago").tag(180)
                    Text("Over a year ago").tag(365)
                    Text("Over 2 years ago").tag(730)
                }
                Picker("Search in", selection: $search.criteria.scope) {
                    Text("Home folder").tag(FileSearchCriteria.Scope.home)
                    Text("This Mac").tag(FileSearchCriteria.Scope.computer)
                }
            } header: {
                heading("Filters", "Peel searches the Spotlight index for files. Folders, apps, and system files aren’t included. What an app keeps in a Library folder is listed last and never selected for you.")
            }
        }
        .formStyle(.grouped)
        // The name is typed in the search field at the top of the column, where other pages filter their lists.
        // Here the field is part of the search, so it is always shown.
        .columnSearch(text: $search.criteria.name, prompt: "Search Files", when: true)
        .navigationTitle(Text(Tool.fileSearch.title))
        .toolbar {
            ToolbarItem {
                RescanButton(isRunning: $isRescanning, isDisabled: !search.criteria.isSearchable || search.isSearching || search.isRemoving) {
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
    }
}
