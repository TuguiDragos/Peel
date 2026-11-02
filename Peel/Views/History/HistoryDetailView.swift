import AppKit
import PeelCore
import SwiftUI

struct HistoryDetailView: View {
    @Environment(RemovalHistoryStore.self) private var history
    @Environment(HelperModel.self) private var helper
    /// Nil until the disk has answered. An empty value would show every record as gone from the Trash for a
    /// moment, and offer to forget records that are still there.
    @State private var standing: RemovalStanding?
    @State private var isAskingToForget = false
    let batch: RemovalBatch

    /// The id of the page's task: the batch, and each time History was read again. When either changes, the page
    /// reads the disk again, since the Trash may have been emptied in the meantime.
    private struct Look: Hashable {
        let batch: RemovalBatch
        let trashLooks: Int
    }

    /// The size of what can still be put back. Until the disk has answered, it is the batch's own total.
    private var restorableSize: SizeTotal {
        standing?.restorableSize ?? batch.size
    }

    var body: some View {
        // A quick Put Back shows nothing, as a quick removal doesn't; the button stays off all the same.
        BusyShown(isBusy: history.isRestoring) { isShowingRestore in
            page(isShowingRestore: isShowingRestore)
        }
    }

    private func page(isShowingRestore: Bool) -> some View {
        List {
            header
                .listRowSeparator(.hidden)
            RemovalsHeldBanner(isOnHistoryPage: true)

            // The records appear only once the disk has answered, so no row changes after it is drawn.
            if let standing {
                records(in: standing, isShowingRestore: isShowingRestore)
            }
        }
        .scrollBarBelowSectionHeaders()
        .edgeBar(.bottom) {
            let selectedCount = standing?.selectedCount(in: history.selectedIDs) ?? 0
            RestoreBar(
                count: selectedCount,
                isRestoring: isShowingRestore,
                isEnabled: selectedCount > 0 && !history.isRestoring && history.mayMove
            ) {
                guard let standing else { return }
                let selected = standing.selected(among: batch.records, in: history.selectedIDs)
                Task { await history.restore(selected, canUseHelper: helper.canAct) }
            }
        }
        .navigationTitle(Text(verbatim: batch.title))
        .toolbar(removing: .title)
        .task(id: Look(batch: batch, trashLooks: history.trashLooks)) {
            let standing = await RemovalStanding.of(batch.records)
            // A look that a newer one replaced leaves its answer.
            guard !Task.isCancelled else { return }
            self.standing = standing
        }
    }

    @ViewBuilder
    private func records(in standing: RemovalStanding, isShowingRestore: Bool) -> some View {
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
                Text("History stops listing what has already left the Trash, so nothing on your Mac changes.")
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
                    record: standing.located(record),
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
        .disabled(isShowingRestore)
    }

    private var header: some View {
        PageHeader(systemImage: batch.tool?.systemImage ?? "clock.arrow.circlepath") {
            Text(verbatim: batch.title)
                .pageTitle()
                .textSelection(.enabled)
                .help(Text(verbatim: batch.title))
        } details: {
            TimelineView(.everyMinute) { _ in
                Text("Moved to the Trash \(batch.date, format: .relative(presentation: .named)), on \(batch.date, format: .dateTime.day().month(.wide).year().hour().minute()).")
            }
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
                    .numberTransition(value: Double(count))
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

private enum RecordNote {
    case sharedStorage
    case loadsAfterARestart
    case editStandsInItsPlace

    var text: LocalizedStringResource {
        switch self {
        case .sharedStorage: "It shared most of its storage with another copy, so moving it freed only its own part."
        case .loadsAfterARestart: "Once put back, macOS loads this audio driver only after you restart your Mac."
        case .editStandsInItsPlace:
            "Your edit of it stands in its place, so Put Back moves that edit to the Trash first, where History keeps it."
        }
    }
}

/// One record's row. It is a view of its own and takes the store rather than a `Binding`, so a change redraws
/// only the row it affects, not the whole batch (see `RowSelection`).
private struct HistoryRecordRow: View {
    let history: RemovalHistoryStore
    /// The record with its places as they are now, which are not where they were when its disk is mounted elsewhere.
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
                hint: hint
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
            Button("Copy Path", systemImage: "doc.on.doc") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(record.originalURL.fullPath, forType: .string)
            }
        }
    }

    /// VoiceOver hears the checkbox and not the lines under it, so its hint says them too.
    private var hint: String? {
        let lines = notes.map { String(localized: $0.text) } + [failure?.explanation].compactMap { $0 }
        return lines.isEmpty ? nil : lines.joined(separator: " ")
    }

    private var notes: [RecordNote] {
        var notes: [RecordNote] = record.sharedStorage == true ? [.sharedStorage] : []
        if place == .inTrash, AudioDrivers.isOne(record.originalURL) { notes.append(.loadsAfterARestart) }
        if place == .inTrash, record.trashedItem.editStandsInItsPlace { notes.append(.editStandsInItsPlace) }
        return notes
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
                    .help(Text(verbatim: record.originalURL.fullPath))
                    .checkboxTitleLine()
                Text(place.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(notes, id: \.self) { note in
                    Text(note.text)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let failure {
                    StatusLabel(title: Text(verbatim: failure.explanation))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 12)
            Text(record.size.byteCount)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }
}
