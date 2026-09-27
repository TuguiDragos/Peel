import PeelCore
import SwiftUI

/// The filters of a search, in a popover from the toolbar. The name is typed in the list's search field.
struct FileSearchForm: View {
    private static let sizes: [Int64] = [10_000_000, 100_000_000, 500_000_000, 1_000_000_000, 5_000_000_000]

    @Environment(FileSearchLibrary.self) private var search

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
        .frame(width: 400)
    }
}
