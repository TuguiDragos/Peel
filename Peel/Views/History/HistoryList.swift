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

    var body: some View {
        @Bindable var history = history
        // Filtered once per body, since the list and the overlay both use the result.
        let listed = batches

        List(listed, selection: $history.selection) { batch in
            HistoryBatchRow(batch: batch)
        }
        .columnSearch(text: $searchText, prompt: "Search History", when: !history.batches.isEmpty)
        .safeAreaBar(edge: .top) {
            Group {
                if let problem = history.problem {
                    HistoryProblemNotice(problem: problem)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                        .transition(.opacity)
                }
            }
            .motion(.settle, .movement, value: history.problem != nil)
        }
        .overlay {
            if history.batches.isEmpty, history.hasLoaded {
                ContentUnavailableView(
                    "Nothing Removed Yet",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("What you move to the Trash with Peel shows up here, and can be put back while it’s still in the Trash.")
                )
            } else if listed.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
        .fadesInColumn(whenRowsChange: history.batches.map(\.id))
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
                detail: Text("Peel isn’t recording new removals, so it doesn’t overwrite what is there.")
            ) { EmptyView() }
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
                Text(verbatim: batch.size.byteCount)
                    .monospacedDigit()
                Text(batch.date, format: .relative(presentation: .named))
                    .help(Text(batch.date, format: .dateTime.day().month(.wide).year().hour().minute()))
            }
            .lineLimit(1)
        }
    }
}
