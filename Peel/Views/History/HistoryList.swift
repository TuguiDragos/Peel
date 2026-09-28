import AppKit
import PeelCore
import SwiftUI

struct HistoryList: View {
    @Environment(RemovalHistoryStore.self) private var history
    @State private var isReloading = false
    @State private var searchText = ""

    /// The batches that match the search, or all of them when the search is empty. History keeps up to
    /// `RemovalLog.maximumRecords` records, so this list can be long.
    private var batches: [RemovalBatch] {
        guard !searchText.isEmpty else { return history.batches }
        return history.batches.filter { batch in history.searchKeys[batch.id].map { SearchText.matches($0, searchText) } == true }
    }

    private var refusals: [RefusalBatch] {
        guard !searchText.isEmpty else { return history.refusalBatches }
        return history.refusalBatches.filter { batch in history.refusalSearchKeys[batch.id].map { SearchText.matches($0, searchText) } == true }
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
        .columnSearch(text: $searchText, prompt: "Search History", when: !history.batches.isEmpty || !history.refusalBatches.isEmpty)
        .safeAreaBar(edge: .top) {
            Group {
                if let problem = history.shownProblem {
                    HistoryProblemNotice(problem: problem)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                        .transition(.opacity)
                }
            }
            .motion(.settle, .movement, value: history.shownProblem != nil)
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
