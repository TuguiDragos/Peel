import AppKit
import PeelCore
import SwiftUI

struct HistoryDetailView: View {
    @Environment(RemovalHistoryStore.self) private var history
    @Environment(HelperModel.self) private var helper
    @Environment(ExclusionsStore.self) private var exclusions
    @Environment(\.controlActiveState) private var controlActiveState
    /// Nil until the disk has answered. An empty value would show every record as gone from the Trash for a
    /// moment, and offer to forget records that are still there.
    @State private var standing: Standing?
    @State private var isAskingToForget = false
    let batch: RemovalBatch

    /// Which records are still in the Trash, which are in the Trash of a disk that isn't connected, and which Peel
    /// can't look at. Any other record has left the Trash. It is read off the main actor, so drawing the page never
    /// touches the disk.
    private struct Standing {
        var inTrash: Set<RemovalRecord.ID> = []
        var away: Set<RemovalRecord.ID> = []
        var notKnown: Set<RemovalRecord.ID> = []

        @concurrent
        static func of(_ records: [RemovalRecord]) async -> Standing {
            var standing = Standing()
            for record in records {
                let place = record.standing
                if place == .inTheTrash {
                    standing.inTrash.insert(record.id)
                } else if !record.isOnAConnectedDisk {
                    standing.away.insert(record.id)
                } else if place == .notKnown {
                    standing.notKnown.insert(record.id)
                }
            }
            return standing
        }

        /// The records among `records` that have left the Trash, looked at again.
        @concurrent
        static func stillGone(_ records: [RemovalRecord]) async -> [RemovalRecord] {
            records.filter { $0.standing == .gone && $0.isOnAConnectedDisk }
        }
    }

    /// The id of the page's task: the batch, and whether the window is key. When either changes, the page reads
    /// the disk again, since the Trash may have been emptied in the meantime.
    private struct Look: Hashable {
        let batch: RemovalBatch
        let isActive: Bool
    }

    private var restorable: [RemovalRecord] {
        batch.records.filter { standing?.inTrash.contains($0.id) == true }
    }

    private var selected: [RemovalRecord] {
        restorable.filter { history.selectedIDs.contains($0.id) }
    }

    /// The size of what can still be put back. Until the disk has answered, it is the batch's own total.
    private var restorableSize: SizeTotal {
        standing == nil ? batch.size : restorable.totalSize
    }

    private var missing: [RemovalRecord] {
        guard let standing else { return [] }
        return batch.records.filter {
            !standing.inTrash.contains($0.id) && !standing.away.contains($0.id) && !standing.notKnown.contains($0.id)
        }
    }

    /// Records Peel can't look at in the Trash. Whether they are still there is not known, so the page never offers
    /// to forget them.
    private var notKnown: [RemovalRecord] {
        batch.records.filter { standing?.notKnown.contains($0.id) == true }
    }

    /// Records in the Trash of a disk that isn't connected. They may still be there, so the page never offers
    /// to forget them.
    private var away: [RemovalRecord] {
        batch.records.filter { standing?.away.contains($0.id) == true }
    }

    var body: some View {
        List {
            header
                .listRowSeparator(.hidden)
            RemovalsHeldBanner(isOnHistoryPage: true)

            // The records appear only once the disk has answered, so no row changes after it is drawn.
            if let standing {
                records(in: standing)
            }
        }
        .safeAreaBar(edge: .bottom) {
            RestoreBar(
                count: selected.count,
                isRestoring: history.isRestoring,
                isEnabled: !selected.isEmpty && !history.isRestoring && exclusions.exclusions.isKnown && !history.isUnreadable
            ) {
                Task { await history.restore(selected, canUseHelper: helper.canAct) }
            }
        }
        .navigationTitle(Text(verbatim: batch.title))
        .toolbar(removing: .title)
        .task(id: Look(batch: batch, isActive: controlActiveState == .key)) {
            standing = await Standing.of(batch.records)
        }
        .task(id: batch.id) {
            // Failures belong to the batch they happened in, so another batch's page starts without them. Keyed to
            // the batch alone: a Put Back that partly worked changes the batch's records, and the alert that
            // reports the rest must stay.
            history.failures = [:]
        }
        .alert("Some items couldn’t be put back.", isPresented: isShowingFailures) {
            Button("OK", role: .cancel) {}
        } message: {
            failureMessage
        }
    }

    @ViewBuilder
    private func records(in standing: Standing) -> some View {
        if !missing.isEmpty {
            Notice(
                title: Text("^[\(missing.count) item](inflect: true) left the Trash"),
                detail: Text("Peel can only put back what is still there.")
            ) {
                Button("Forget") {
                    isAskingToForget = true
                }
                .tint(.red)
            }
            .listRowSeparator(.hidden)
            .confirmationDialog(Text("Forget ^[\(missing.count) item](inflect: true)?"), isPresented: $isAskingToForget) {
                Button("Forget", role: .destructive) {
                    // Looked at again first: an item can come back to the Trash, or stop being visible, meanwhile.
                    Task { await history.forget(await Standing.stillGone(missing)) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("What History forgets, it can’t put back afterwards.")
            }
        }

        if !notKnown.isEmpty {
            Notice(
                title: Text("Peel can’t look in the Trash right now"),
                detail: Text("History keeps what it can’t see until Peel can look again."),
                kind: .note
            ) {}
            .listRowSeparator(.hidden)
        }

        if !away.isEmpty {
            Notice(
                title: Text("^[\(away.count) item](inflect: true) on a disk that isn’t connected"),
                detail: Text("Connect the disk to put them back from its Trash."),
                kind: .note
            ) {}
            .listRowSeparator(.hidden)
        }

        Section {
            ForEach(Array(batch.records.enumerated()), id: \.element.id) { index, record in
                HistoryRecordRow(
                    history: history,
                    record: record,
                    place: place(of: record, in: standing),
                    isSelected: history.isSelected(record),
                    isFirst: index == 0
                )
            }
            .listRowSeparator(.hidden)
        } header: {
            SectionHeaderLine {
                Text("Items")
            } actions: {
                SelectAllButton(selectable: restorable.map(\.id), selection: Bindable(history).selectedIDs)
            }
        }
        .disabled(history.isRestoring)
    }

    private var header: some View {
        PageHeader(systemImage: batch.tool?.systemImage ?? "clock.arrow.circlepath") {
            Text(verbatim: batch.title)
                .pageTitle()
                .textSelection(.enabled)
                .help(Text(verbatim: batch.title))
        } details: {
            Text("Moved to the Trash \(batch.date, format: .relative(presentation: .named)), on \(batch.date, format: .dateTime.day().month(.wide).year().hour().minute()).")
                .font(.callout)
                .foregroundStyle(.secondary)
            FlowLayout {
                ForEach(batch.tools, id: \.self) { tool in
                    Badge(title: Text(tool.title), systemImage: tool.systemImage)
                }
                Badge(title: Text("^[\(batch.records.count) item](inflect: true)"), systemImage: "doc.on.doc")
            }
            .padding(.top, 2)
        } trailing: {
            // VoiceOver reads the figure and its caption as one element, since `TotalLabel` combines them.
            TotalLabel(
                total: restorableSize,
                caption: standing == nil ? Text("moved") : Text("to put back")
            )
        }
    }

    private func place(of record: RemovalRecord, in standing: Standing) -> RecordPlace {
        if standing.inTrash.contains(record.id) { return .inTrash }
        if standing.away.contains(record.id) { return .onADiskThatIsAway }
        if standing.notKnown.contains(record.id) { return .notKnown }
        return .gone
    }

    private var isShowingFailures: Binding<Bool> {
        Binding(
            get: { batch.records.contains { history.failures[$0.id] != nil } },
            set: { if !$0 { history.failures = [:] } }
        )
    }

    /// The alert's message: each item that couldn't be put back, with its own reason, since items can fail
    /// for different reasons.
    private var failureMessage: Text {
        let lines = history.failures.compactMap { id, failure -> String? in
            guard let record = batch.records.first(where: { $0.id == id }) else { return nil }
            return "\(record.originalURL.abbreviatedPath)\n\(failure.explanation)"
        }
        return Text(verbatim: lines.sorted().joined(separator: "\n\n"))
    }
}

private struct RestoreBar: View {
    let count: Int
    let isRestoring: Bool
    let isEnabled: Bool
    let onRestore: () -> Void

    var body: some View {
        FloatingBar {
            if isRestoring {
                ProgressView()
                    .controlSize(.small)
                Text("Putting back…")
                    .foregroundStyle(.secondary)
            } else {
                Text("^[\(count) item](inflect: true)")
                    .font(.barFigure)
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(count)))
                Text("Selected")
                    .foregroundStyle(.secondary)
            }
        } action: {
            // No Command-Z shortcut: the Edit menu's Undo already uses that key, and someone undoing a typo in
            // the list's search field is not asking to put the selected files back.
            Button("Put Back", systemImage: "arrow.uturn.backward", action: onRestore)
                .disabled(!isEnabled)
        }
        .motion(value: count)
        .motion(value: isRestoring)
    }
}

/// Where a removed item is, as read from the disk.
private enum RecordPlace {
    case inTrash
    case onADiskThatIsAway
    case notKnown
    case gone

    var symbolName: String { self == .inTrash ? "trash" : "questionmark.circle" }

    var title: LocalizedStringResource {
        switch self {
        case .gone: "No longer in the Trash"
        case .inTrash: "In the Trash"
        case .onADiskThatIsAway: "On a disk that isn’t connected"
        case .notKnown: "Peel can’t look in the Trash right now"
        }
    }
}

/// One record's row. It is a view of its own and takes the store rather than a `Binding`, so a change redraws
/// only the row it affects, not the whole batch (see `RowSelection`).
private struct HistoryRecordRow: View {
    let history: RemovalHistoryStore
    let record: RemovalRecord
    let place: RecordPlace
    let isSelected: Bool
    var isFirst = false

    var body: some View {
        HStack(alignment: .checkboxTitleLine, spacing: 5) {
            NativeCheckbox(
                isOn: Binding(get: { isSelected }, set: { history.setSelected($0, record) }),
                label: [record.originalURL.abbreviatedPath, String(localized: place.title), record.size.byteCount]
                    .joined(separator: ", ")
            )
            item
                .contentShape(.rect)
                .onTapGesture { history.setSelected(!isSelected, record) }
                .checkboxTitle()
                // The checkbox's label already reads the record.
                .accessibilityHidden(true)
        }
        .disabled(place != .inTrash)
        .tableRow(isFirst: isFirst)
        .contextMenu {
            if place == .inTrash {
                Button("Show in Finder", systemImage: "folder") {
                    NSWorkspace.shared.activateFileViewerSelecting([record.trashedURL])
                }
            }
        }
    }

    private var item: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: place.symbolName)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(record.originalURL.abbreviatedPath)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .checkboxTitleLine()
                Text(place.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            Text(record.size.byteCount)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }
}
