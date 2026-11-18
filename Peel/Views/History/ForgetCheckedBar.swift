import PeelCore
import SwiftUI

/// History's bar for the entries its list has checked: how many, and Forget, which looks at the disk first, asks with
/// what it found, and looks again before it forgets.
struct ForgetCheckedBar: View {
    @Environment(RemovalHistoryStore.self) private var history
    /// The checked removals and Not Moved entries the list shows.
    let removals: [RemovalBatch]
    let entries: [RefusalBatch]
    /// How many looks were asked for. Each starts the bar's look, which leaving the page stops.
    @State private var looks = 0
    @State private var isLooking = false
    /// What the last look found, while its question or its answer is shown.
    @State private var found: Found?

    /// What Forget would take away: what has left the Trash from the checked removals, and the checked entries whole.
    struct Found {
        let leftTheTrash: LeftTheTrash
        let entries: Set<RefusalBatch.ID>

        var isEmpty: Bool { leftTheTrash.records.isEmpty && entries.isEmpty }
    }

    var body: some View {
        let count = removals.count + entries.count
        FloatingBar {
            Text("^[\(count) entry](inflect: true)")
                .font(.barFigure)
                .monospacedDigit()
                .numberTransition(value: Double(count))
            Text("Selected", comment: "A label after a figure at the foot of a page: a size, such as 303 kB, or a count, such as 3 items. Write it so it reads right after any figure, as \"en la selección\" does, never as a form that agrees with the number or adds (s).")
                .foregroundStyle(.secondary)
        } action: {
            BusyShown(isBusy: isLooking) { isShown in
                Button("Forget…", systemImage: "eraser") { looks += 1 }
                    .disabled(isShown || history.isRestoring || !history.mayMove)
                    .help(history.holdingReason.map { Text(verbatim: $0.explanation) } ?? Text("Forget…"))
            }
        }
        .motion(value: count)
        .task(id: looks) {
            guard looks > 0 else { return }
            isLooking = true
            let left = await RemovalStanding.leftTheTrash(removals.flatMap(\.records))
            isLooking = false
            // A look the page has left asks nothing.
            guard !Task.isCancelled else { return }
            found = Found(leftTheTrash: left, entries: Set(entries.map(\.id)))
        }
        .confirmationDialog(
            Text(verbatim: found.flatMap(Self.question) ?? ""),
            isPresented: Binding(get: { found.flatMap(Self.question) != nil }, set: { if !$0 { found = nil } }),
            presenting: found
        ) { found in
            Button("Forget", role: .destructive) {
                Task { await history.forgetChecked(found.leftTheTrash, entries: found.entries) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { found in
            Text(verbatim: Self.message(for: found))
        }
        .alert(
            Text("Nothing selected has left the Trash"),
            isPresented: Binding(get: { found?.isEmpty == true }, set: { if !$0 { found = nil } })
        ) {
            Button("OK") {}
        } message: {
            Text("What is still in the Trash stays listed, so Put Back can bring it back.")
        }
    }

    /// The question for what a look found, or nil when there is nothing to forget.
    static func question(for found: Found) -> String? {
        let items = found.leftTheTrash.records.count
        let removals = found.leftTheTrash.removals
        let entries = found.entries.count
        // An alert's title is drawn as plain text, which leaves inflection markup as written.
        return switch (items > 0, entries > 0) {
        case (true, false):
            String(inflecting: "Forget ^[\(items) item](inflect: true) in ^[\(removals) removal](inflect: true)?")
        case (false, true): String(inflecting: "Forget ^[\(entries) entry](inflect: true) under Not Moved?")
        case (true, true):
            String(inflecting: "Forget ^[\(items) item](inflect: true) in ^[\(removals) removal](inflect: true) and ^[\(entries) entry](inflect: true) under Not Moved?")
        case (false, false): nil
        }
    }

    /// What forgetting changes, a sentence for each kind of entry the question names.
    static func message(for found: Found) -> String {
        [
            found.leftTheTrash.records.isEmpty
                ? nil : String(localized: "History stops listing what has left the Trash, so nothing on your Mac changes. What is still in the Trash stays listed, with Put Back."),
            found.entries.isEmpty
                ? nil : String(localized: "Not Moved stops listing them, and what they name stays where it is."),
        ].compactMap(\.self).joined(separator: "\n\n")
    }
}
