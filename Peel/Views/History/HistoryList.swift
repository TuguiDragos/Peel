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
    /// Pejax's filter: only the removals that can no longer be put back, since all they moved has left the Trash.
    @State private var showsOnlyWhatLeft = false
    /// The removals all of whose items have left the Trash, while the filter is on and once Peel has looked.
    @State private var leftTheTrash: Set<RemovalBatch.ID>?

    private struct Found {
        let batches: [RemovalBatch]
        let refusals: [RefusalBatch]
    }

    /// What starts the search again: other words, or other lists.
    private struct Search: Hashable {
        let text: String
        let revision: Int
    }

    /// What starts the filter's look again: turning it on, or other lists.
    private struct Look: Hashable {
        let isOn: Bool
        let revision: Int
    }

    private var batches: [RemovalBatch] {
        let all = searchText.isEmpty ? history.batches : found?.batches ?? history.batches
        guard showsOnlyWhatLeft else { return all }
        return all.filter { leftTheTrash?.contains($0.id) == true }
    }

    private var refusals: [RefusalBatch] {
        guard !showsOnlyWhatLeft else { return [] }
        return searchText.isEmpty ? history.refusalBatches : found?.refusals ?? history.refusalBatches
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
        String(inflecting: "It keeps only its latest removals, up to ^[\(RefusalLog.maximumRecords) item](inflect: true). What the older ones could not move stayed where it was.")
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
                        title: Text("Peel kept ^[\(copies.count) copy](inflect: true) of History it could not read"),
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
        .edgeBar(.bottom) {
            let removals = listed.filter { history.checkedRemovals.contains($0.id) }
            let entries = refused.filter { history.checkedRefusals.contains($0.id) }
            if !removals.isEmpty || !entries.isEmpty {
                ForgetCheckedBar(removals: removals, entries: entries)
            }
        }
        .focusedSceneValue(\.selectRows, listed.isEmpty && refused.isEmpty ? nil : selectCommands(listed, refused))
        .overlay {
            if !history.hasLoaded || showsOnlyWhatLeft && leftTheTrash == nil {
                ProgressView()
            } else if showsOnlyWhatLeft, listed.isEmpty {
                ContentUnavailableView(
                    "Nothing Has Left the Trash",
                    systemImage: "trash",
                    description: Text("Everything these removals moved is still in the Trash, so Put Back can bring it back.")
                )
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
                Toggle(isOn: $showsOnlyWhatLeft) {
                    Label("Show Only What Left the Trash", systemImage: "line.3.horizontal.decrease")
                }
                .toggleStyle(.button)
                .help(Text("Show Only What Left the Trash"))
                .disabled(!history.hasLoaded || history.batches.isEmpty && !showsOnlyWhatLeft)
            }
            ToolbarItem {
                Menu {
                    Button("Select All") { check(listed, refused) }
                    Button("Deselect All") { uncheck() }
                } label: {
                    ToolbarMenuLabel(title: "Select", systemImage: "checklist")
                }
                .disabled(listed.isEmpty && refused.isEmpty)
            }
            ToolbarItem {
                RescanButton(isRunning: $isReloading, title: "Reload") {
                    await history.reload()
                }
            }
        }
        .task {
            await history.load()
        }
        .task(id: Look(isOn: showsOnlyWhatLeft, revision: history.revision)) {
            guard showsOnlyWhatLeft else {
                leftTheTrash = nil
                return
            }
            let left = await RemovalStanding.leftTheTrash(history.records)
            guard !Task.isCancelled else { return }
            let gone = Set(left.records.map(\.id))
            leftTheTrash = Set(history.batches.filter { $0.records.allSatisfy { gone.contains($0.id) } }.map(\.id))
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

extension HistoryList {
    private func check(_ removals: [RemovalBatch], _ entries: [RefusalBatch]) {
        history.checkedRemovals.formUnion(removals.map(\.id))
        history.checkedRefusals.formUnion(entries.map(\.id))
    }

    private func uncheck() {
        history.checkedRemovals = []
        history.checkedRefusals = []
    }

    /// Select All and Deselect All in the Edit menu, which the keyboard reaches, for what the list shows.
    private func selectCommands(_ removals: [RemovalBatch], _ entries: [RefusalBatch]) -> SelectCommands {
        let isAnyChecked = removals.contains { history.checkedRemovals.contains($0.id) }
            || entries.contains { history.checkedRefusals.contains($0.id) }
        return SelectCommands(
            recommended: nil,
            all: MenuCommand(title: "Select All", isEnabled: true) { check(removals, entries) },
            none: MenuCommand(title: "Deselect All", isEnabled: isAnyChecked) { uncheck() }
        )
    }
}

private struct HistoryProblemNotice: View {
    @Environment(RemovalHistoryStore.self) private var history
    let problem: RemovalLogProblem

    var body: some View {
        switch problem {
        case .damaged(let setAside):
            Notice(
                title: Text("History was damaged"),
                detail: Text("Peel kept the old file and continued with what it could still read. Items already in the Trash are still there: you can drag them back out in Finder.")
            ) {
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([setAside])
                }
            }
        case .unreadable(let why):
            Notice(
                title: Text("Peel couldn’t read History"),
                detail: Text(verbatim: why.said(after: String(localized: "Until it can read History, or you start over, Peel removes nothing, because anything it moved now could not be put back. Starting over keeps the old file beside a new one. Items it lists can then only be dragged back out of the Trash in Finder."), about: history.historyFile))
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
                title: Text("Peel could not read its record of a removal under way"),
                detail: Text("Peel kept that file aside. If a removal was cut short, what it moved is in the Trash but is not listed here: you can drag it back out in Finder.")
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
    @Environment(RemovalHistoryStore.self) private var history
    let batch: RemovalBatch

    private var isChecked: Binding<Bool> {
        Binding(
            get: { history.checkedRemovals.contains(batch.id) },
            set: { isOn in
                if isOn { history.checkedRemovals.insert(batch.id) } else { history.checkedRemovals.remove(batch.id) }
            }
        )
    }

    var body: some View {
        HStack(spacing: 10) {
            NativeCheckbox(isOn: isChecked, label: batch.title, help: String(localized: "Select to forget it in History"))
            row
        }
    }

    private var row: some View {
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
    @Environment(RemovalHistoryStore.self) private var history
    let batch: RefusalBatch

    private var isChecked: Binding<Bool> {
        Binding(
            get: { history.checkedRefusals.contains(batch.id) },
            set: { isOn in
                if isOn { history.checkedRefusals.insert(batch.id) } else { history.checkedRefusals.remove(batch.id) }
            }
        )
    }

    var body: some View {
        HStack(spacing: 10) {
            NativeCheckbox(isOn: isChecked, label: batch.title, help: String(localized: "Select to forget it in History"))
            row
        }
    }

    private var row: some View {
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
