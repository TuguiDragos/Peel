import AppKit
import PeelCore
import SwiftUI

struct HistoryList: View {
    @Environment(RemovalHistoryStore.self) private var history
    @Environment(LifetimeStats.self) private var stats
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

    private var hasNotices: Bool {
        history.shownProblem != nil || history.refusalProblem != nil || history.untoldNoLongerListed != nil
            || history.untoldRefusalsNoLongerListed != nil || !history.untoldSetAsideCopies.isEmpty
    }

    /// What the page says under each count of older removals left out, with the limit that left them out.
    static var historyKeepsItsLatest: String {
        String(inflecting: "It keeps only its latest removals, up to ^[\(RemovalLog.maximumRecords) item](inflect: true). What the older ones moved is still in the Trash unless you emptied it.")
    }

    static var notMovedKeepsItsLatest: String {
        String(inflecting: "It keeps only its latest removals, up to ^[\(RefusalLog.maximumRecords) item](inflect: true). What the older ones couldn’t move stayed where it was.")
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
        .accessibilityLabel(Text(Tool.history.title))
        .scrollBarBelowSectionHeaders(!history.batches.isEmpty && !history.refusalBatches.isEmpty)
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
                // Said once: the page has said it when it goes away.
                let copies = history.untoldSetAsideCopies
                if !copies.isEmpty {
                    Notice(
                        title: Text("Peel kept ^[\(copies.count) copy](inflect: true) of History it couldn’t read"),
                        detail: Text("It started History again and kept those files beside it. What their removals moved is in the Trash unless you emptied it."),
                        kind: .note
                    ) {
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting(copies) }
                    }
                    .transition(.opacity)
                }
                if let count = history.untoldNoLongerListed {
                    Notice(
                        title: Text("History no longer lists ^[\(count) older removal](inflect: true)"),
                        detail: Text(verbatim: Self.historyKeepsItsLatest),
                        kind: .note
                    ) { EmptyView() }
                    .transition(.opacity)
                    .onDisappear { history.tellNoLongerListed(count) }
                }
                if let count = history.untoldRefusalsNoLongerListed {
                    Notice(
                        title: Text("Not Moved no longer lists ^[\(count) older removal](inflect: true)"),
                        detail: Text(verbatim: Self.notMovedKeepsItsLatest),
                        kind: .note
                    ) { EmptyView() }
                    .transition(.opacity)
                    .onDisappear { history.tellRefusalsNoLongerListed(count) }
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, hasNotices ? 8 : 0)
            .motion(.settle, .movement, value: history.shownProblem != nil)
            .motion(.settle, .movement, value: history.refusalProblem != nil)
            .motion(.settle, .movement, value: history.untoldNoLongerListed != nil)
            .motion(.settle, .movement, value: history.untoldSetAsideCopies.isEmpty)
        }
        .overlay {
            if !history.hasLoaded {
                ProgressView()
            } else if history.isKnownEmpty {
                // Put Back and Forget can empty a History Peel did write to.
                ContentUnavailableView(
                    stats.hasCleaned || history.noLongerListed > 0 ? "No Removals" : "Nothing Removed Yet",
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
                    await history.reload()
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
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([setAside])
                }
            }
        case .unreadable(let why):
            Notice(
                title: Text("The record of past removals can’t be read"),
                detail: Text(verbatim: why.said(after: String(localized: "Until it can read the record, or you start over, Peel removes nothing, because anything it moved now couldn’t be put back. Starting over keeps the old file beside a new one. Items it lists can then only be dragged back out of the Trash in Finder."), about: history.historyFile))
            ) {
                StartOverButton(file: history.historyFile, startedOver: "Started History over.") {
                    await history.startOver()
                }
            }
        case .couldNotRecord(let why):
            Notice(
                title: Text("The last removal couldn’t be recorded"),
                detail: Text(verbatim: why.said(after: String(localized: "The items are in the Trash. You can drag them back out in Finder."), about: history.historyFile))
            ) { EmptyView() }
        case .couldNotUpdate(let why):
            Notice(
                title: Text("History couldn’t be updated"),
                detail: Text(verbatim: why.said(after: String(localized: "What you put back or forgot may still be listed here, because the record couldn’t be saved."), about: history.historyFile))
            ) { EmptyView() }
        case .journalSetAside(let setAside):
            Notice(
                title: Text("Peel couldn’t read its record of a removal under way"),
                detail: Text("Peel kept that file aside. If a removal was cut short, what it moved is in the Trash but isn’t listed here: you can drag it back out in Finder.")
            ) {
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([setAside])
                }
            }
        }
    }
}

/// What kept the list under Not Moved from being read or saved.
private struct RefusalProblemNotice: View {
    @Environment(RemovalHistoryStore.self) private var history
    let problem: RefusalLogProblem

    var body: some View {
        switch problem {
        case .damaged(let setAside):
            Notice(
                title: Text("The Not Moved list was damaged"),
                detail: Text("Peel kept the old file and continued with what it could still read.")
            ) {
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([setAside])
                }
            }
        case .unreadable(let why):
            Notice(
                title: Text("The Not Moved list can’t be read"),
                detail: Text(verbatim: why.said(after: String(localized: "Until you start the list over, Peel adds nothing to it, since it is the only record of what stayed. Starting over keeps the old file beside a new one."), about: history.refusalsFile))
            ) {
                StartOverButton(file: history.refusalsFile, startedOver: "Started the Not Moved list over.") {
                    await history.startOverRefusals()
                }
            }
        case .couldNotRecord(let why):
            Notice(
                title: Text("The Not Moved list couldn’t be saved"),
                detail: Text(verbatim: why.said(after: String(localized: "What stayed in the last removal is where it was, but it isn’t listed here."), about: history.refusalsFile))
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
                TimelineView(.everyMinute) { _ in
                    Text(batch.date, format: .relative(presentation: .named))
                }
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
                TimelineView(.everyMinute) { _ in
                    Text(batch.date, format: .relative(presentation: .named))
                }
                    .help(Text(batch.date, format: .dateTime.day().month(.wide).year().hour().minute()))
            }
            .lineLimit(1)
        }
    }
}
