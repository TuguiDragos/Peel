import AppKit
import PeelCore
import SwiftUI

struct HistoryDetailView: View {
    @Environment(RemovalHistoryStore.self) private var history
    @Environment(HelperModel.self) private var helper
    @Environment(ExclusionsStore.self) private var exclusions
    @Environment(\.controlActiveState) private var controlActiveState
    @Environment(\.openSettings) private var openSettings
    /// Nil until the disk has answered. An empty value would show every record as gone from the Trash for a
    /// moment, and offer to forget records that are still there.
    @State private var standing: RemovalStanding?
    @State private var isAskingToForget = false
    /// The alert after a Put Back that left items behind. Its reasons stay under the rows once it is closed.
    @State private var isShowingFailures = false
    /// This batch's items that stayed in the Trash, in the order the page lists them.
    @State private var failures: [(record: RemovalRecord, failure: RestoreFailure)] = []
    let batch: RemovalBatch

    /// The id of the page's task: the batch, and whether the window is key. When either changes, the page reads
    /// the disk again, since the Trash may have been emptied in the meantime.
    private struct Look: Hashable {
        let batch: RemovalBatch
        let isActive: Bool
    }

    /// The size of what can still be put back. Until the disk has answered, it is the batch's own total.
    private var restorableSize: SizeTotal {
        standing?.restorableSize ?? batch.size
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
            let selectedCount = standing?.selectedCount(in: history.selectedIDs) ?? 0
            RestoreBar(
                count: selectedCount,
                isRestoring: history.isRestoring,
                isEnabled: selectedCount > 0 && !history.isRestoring && exclusions.exclusions.isKnown && !history.isUnreadable
            ) {
                guard let standing else { return }
                let selected = standing.selected(among: batch.records, in: history.selectedIDs)
                Task { await history.restore(selected, canUseHelper: helper.canAct) }
            }
        }
        .navigationTitle(Text(verbatim: batch.title))
        .toolbar(removing: .title)
        .task(id: Look(batch: batch, isActive: controlActiveState == .key)) {
            standing = await RemovalStanding.of(batch.records)
        }
        .task(id: batch.id) {
            // Failures belong to the batch they happened in, so another batch's page starts without them. Keyed to
            // the batch alone: a Put Back that partly worked changes the batch's records, and the alert that
            // reports the rest must stay.
            history.failures = [:]
        }
        .onChange(of: history.failures) { _, all in
            failures = batch.records.compactMap { record in all[record.id].map { (record, $0) } }
            isShowingFailures = !failures.isEmpty
        }
        .alert("Some items couldn’t be put back.", isPresented: $isShowingFailures) {
            if failures.contains(where: { $0.failure == .needsHelper }) {
                Button("Open Peel Settings") { SettingsPane.helper.open(with: openSettings) }
            }
            Button("Copy Details") { copyFailureDetails() }
            Button("OK", role: .cancel) {}
        } message: {
            failureMessage
        }
    }

    @ViewBuilder
    private func records(in standing: RemovalStanding) -> some View {
        if standing.missingCount > 0 {
            Notice(
                title: Text("^[\(standing.missingCount) item](inflect: true) left the Trash"),
                detail: Text("Peel can only put back what is still there.")
            ) {
                Button("Forget") {
                    isAskingToForget = true
                }
                .tint(.red)
            }
            .listRowSeparator(.hidden)
            .confirmationDialog(Text(verbatim: String(inflecting: "Forget ^[\(standing.missingCount) item](inflect: true)?")), isPresented: $isAskingToForget) {
                Button("Forget", role: .destructive) {
                    // Looked at again first: an item can come back to the Trash, or stop being visible, meanwhile.
                    let missing = standing.missing(among: batch.records)
                    Task { await history.forget(await RemovalStanding.stillGone(missing)) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("What History forgets, it can’t put back afterwards.")
            }
        }

        // Whether these are still in the Trash is not known, so the page never offers to forget them.
        if !standing.notKnown.isEmpty {
            Notice(
                title: Text("Peel can’t look in the Trash right now"),
                detail: Text("History keeps what it can’t see until Peel can look again."),
                kind: .note
            ) {}
            .listRowSeparator(.hidden)
        }

        // They may still be in the Trash of their disk, so the page never offers to forget them.
        if !standing.away.isEmpty {
            Notice(
                title: Text("^[\(standing.away.count) item](inflect: true) on a disk that isn’t connected"),
                detail: Text("Connect the disk to put them back from its Trash."),
                kind: .note
            ) {}
            .listRowSeparator(.hidden)
        }

        Section {
            ForEach(batch.records) { record in
                HistoryRecordRow(
                    history: history,
                    record: record,
                    place: place(of: record, in: standing),
                    failure: history.failures[record.id],
                    isSelected: history.isSelected(record),
                    isFirst: record.id == batch.records.first?.id
                )
            }
            .listRowSeparator(.hidden)
        } header: {
            SectionHeaderLine {
                Text("Items")
            } actions: {
                SelectAllButton(
                    selectable: standing.restorable,
                    rows: batch.records.map(\.id),
                    selection: Bindable(history).selectedIDs
                )
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

    private func place(of record: RemovalRecord, in standing: RemovalStanding) -> RecordPlace {
        if standing.inTrash.contains(record.id) { return .inTrash }
        if standing.away.contains(record.id) { return .onADiskThatIsAway }
        if standing.notKnown.contains(record.id) { return .notKnown }
        return .gone
    }

    /// The alert's message: the first few items that couldn't be put back, each with its own reason, since items
    /// can fail for different reasons, and how many more there are.
    private var failureMessage: Text {
        let failures = failures
        var lines = failures.prefix(RemovalFailureAlert.mostListed).map {
            "\($0.record.originalURL.abbreviatedPath)\n\($0.failure.explanation)"
        }
        let rest = failures.count - lines.count
        if rest > 0 {
            lines.append(String(inflecting: "And ^[\(rest) more item](inflect: true)."))
        }
        return Text(verbatim: lines.joined(separator: "\n\n"))
    }

    /// Copies every item with its full path, since the alert lists only the first few and its text can't be
    /// selected.
    private func copyFailureDetails() {
        let lines = failures.map { "\($0.record.originalURL.path(percentEncoded: false))\n\($0.failure.explanation)" }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n\n"), forType: .string)
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
                Text("Selected", comment: "A label after a figure at the foot of a page: a size, such as 303 kB, or a count, such as 3 items. Write it so it reads right after any figure, as \"en la selección\" does, never as a form that agrees with the number or adds (s).")
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
    /// Why the last Put Back left this item in the Trash, said under it.
    let failure: RestoreFailure?
    let isSelected: Bool
    var isFirst = false

    var body: some View {
        HStack(alignment: .checkboxTitleLine, spacing: 5) {
            NativeCheckbox(
                isOn: Binding(get: { isSelected }, set: { history.setSelected($0, record) }),
                label: [record.originalURL.abbreviatedPath, String(localized: place.title), record.size.byteCount]
                    .joined(separator: ", "),
                hint: failure?.explanation
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
                if let failure {
                    Label(failure.explanation, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            Spacer(minLength: 12)
            Text(record.size.byteCount)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }
}
