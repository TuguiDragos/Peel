import AppKit
import PeelCore
import SwiftUI

struct HistoryList: View {
    @Environment(RemovalHistoryStore.self) private var history
    @State private var isReloading = false
    @State private var searchText = ""
    /// What the search found, worked out off the main actor, since a removal's key names every item in it. Kept while
    /// the next answer is worked out.
    @State private var found: Found?

    private struct Found {
        let batches: [RemovalBatch]
        let refusals: [RefusalBatch]
    }

    /// What starts the search again: other words, or other lists.
    private struct Search: Hashable {
        let text: String
        let revision: Int
    }

    private var batches: [RemovalBatch] {
        searchText.isEmpty ? history.batches : found?.batches ?? history.batches
    }

    private var refusals: [RefusalBatch] {
        searchText.isEmpty ? history.refusalBatches : found?.refusals ?? history.refusalBatches
    }

    var body: some View {
        @Bindable var history = history
        // Filtered once per body, since the list and the overlay both use the result.
        let listed = batches
        let refused = refusals

        List(selection: $history.selection) {
            ForEach(listed) { batch in
                HistoryBatchRow(batch: batch)
            }
            // No heading when the list would start with it: a list that begins with a heading and fills all at
            // once keeps its rows at the table's default height.
            if listed.isEmpty {
                ForEach(refused) { RefusalBatchRow(batch: $0) }
            } else if !refused.isEmpty {
                Section {
                    ForEach(refused) { RefusalBatchRow(batch: $0) }
                } header: {
                    Text("Not Moved")
                }
            }
        }
        .scrollBarBelowSectionHeaders(!listed.isEmpty && !refused.isEmpty)
        .columnSearch(text: $searchText, prompt: "Search History", when: !history.batches.isEmpty || !history.refusalBatches.isEmpty)
        .edgeBar(.top) {
            VStack(spacing: 8) {
                if let problem = history.shownProblem {
                    HistoryProblemNotice(problem: problem)
                        .transition(.opacity)
                }
                if let problem = history.refusalProblem {
                    RefusalProblemNotice(problem: problem)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, history.shownProblem != nil || history.refusalProblem != nil ? 8 : 0)
            .motion(.settle, .movement, value: history.shownProblem != nil)
            .motion(.settle, .movement, value: history.refusalProblem != nil)
        }
        .overlay {
            if !history.hasLoaded {
                ProgressView()
            } else if history.batches.isEmpty, history.refusalBatches.isEmpty {
                ContentUnavailableView(
                    "Nothing Removed Yet",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("What you move to the Trash with Peel shows up here, and can be put back while it’s still in the Trash.")
                )
            } else if listed.isEmpty, refused.isEmpty, !searchText.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
        .fadesInColumn(whenRowsChange: history.batches.map(\.id) + history.refusalBatches.map(\.id))
        .navigationTitle(Text(Tool.history.title))
        // Every tool has a button in the toolbar, so the window keeps one height from page to page.
        .toolbar {
            ToolbarItem {
                RescanButton(isRunning: $isReloading, title: "Reload") {
                    await history.load()
                }
            }
        }
        .task {
            await history.load()
        }
        .task(id: Search(text: searchText, revision: history.revision)) {
            guard !searchText.isEmpty else {
                found = nil
                return
            }
            guard let batches = await SearchText.matching(searchText, among: history.batches, keys: history.searchKeys),
                  let refusals = await SearchText.matching(
                      searchText,
                      among: history.refusalBatches,
                      keys: history.refusalSearchKeys
                  )
            else { return }
            found = Found(batches: batches, refusals: refusals)
        }
    }
}

private struct HistoryProblemNotice: View {
    @Environment(RemovalHistoryStore.self) private var history
    let problem: RemovalLogProblem

    var body: some View {
        switch problem {
        case .damaged(let setAside):
            Notice(
                title: Text("The record of past removals was damaged"),
                detail: Text("Peel kept the old file and continued with what it could still read. Items already in the Trash are still there: you can drag them back out in Finder.")
            ) {
                Button("Show in Finder", systemImage: "folder") {
                    NSWorkspace.shared.activateFileViewerSelecting([setAside])
                }
                }
        case .unreadable:
            Notice(
                title: Text("The record of past removals can’t be read"),
                detail: Text("Until it can read the record, or you start over, Peel removes nothing, because anything it moved now couldn’t be put back. Starting over keeps the old file beside a new one.")
            ) {
                Button("Start Over") {
                    Task { await history.startOver() }
                }
            }
        case .couldNotRecord:
            Notice(
                title: Text("The last removal couldn’t be recorded"),
                detail: Text("The items are in the Trash. You can drag them back out in Finder.")
            ) { EmptyView() }
        case .couldNotUpdate:
            Notice(
                title: Text("History couldn’t be updated"),
                detail: Text("What you put back or forgot may still be listed here, because the record couldn’t be saved.")
            ) { EmptyView() }
        }
    }
}

/// What kept the list under Not Moved from being read or saved.
private struct RefusalProblemNotice: View {
    let problem: RefusalLogProblem

    var body: some View {
        switch problem {
        case .damaged(let setAside):
            Notice(
                title: Text("The Not Moved list was damaged"),
                detail: Text("Peel kept the old file and continued with what it could still read.")
            ) {
                Button("Show in Finder", systemImage: "folder") {
                    NSWorkspace.shared.activateFileViewerSelecting([setAside])
                }
            }
        case .unreadable:
            Notice(
                title: Text("The Not Moved list can’t be read"),
                detail: Text("Peel leaves the file as it is and adds nothing to it, since it is the only record of what stayed.")
            ) { EmptyView() }
        case .couldNotRecord:
            Notice(
                title: Text("The Not Moved list couldn’t be saved"),
                detail: Text("What stayed in the last removal is where it was, but it isn’t listed here.")
            ) { EmptyView() }
        }
    }
}

private struct HistoryBatchRow: View {
    let batch: RemovalBatch

    var body: some View {
        ToolRow(systemImage: batch.tool?.systemImage ?? "clock.arrow.circlepath") {
            Text(verbatim: batch.title)
                .lineLimit(1)
                .truncationMode(.middle)
        } details: {
            HStack(spacing: 6) {
                Text("^[\(batch.records.count) item](inflect: true)")
                Text(verbatim: batch.size.text)
                    .monospacedDigit()
                Text(batch.date, format: .relative(presentation: .named))
                    .help(Text(batch.date, format: .dateTime.day().month(.wide).year().hour().minute()))
            }
            .lineLimit(1)
        }
    }
}

/// One removal's refusals: what Peel was asked to move and did not.
private struct RefusalBatchRow: View {
    let batch: RefusalBatch

    var body: some View {
        ToolRow(systemImage: "nosign") {
            Text(verbatim: batch.title)
                .lineLimit(1)
                .truncationMode(.middle)
        } details: {
            HStack(spacing: 6) {
                Text("^[\(batch.records.count) item](inflect: true) not moved")
                Text(batch.date, format: .relative(presentation: .named))
                    .help(Text(batch.date, format: .dateTime.day().month(.wide).year().hour().minute()))
            }
            .lineLimit(1)
        }
    }
}
