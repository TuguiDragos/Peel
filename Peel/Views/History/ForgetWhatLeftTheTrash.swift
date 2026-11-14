import PeelCore
import SwiftUI

/// History's action for everything it lists that has left the Trash: Peel looks at the disk when it is chosen, asks
/// with what it found, and looks again before it forgets.
struct ForgetWhatLeftTheTrash: View {
    @Environment(RemovalHistoryStore.self) private var history
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// How many looks were asked for. Each starts the page's look, which leaving the page stops.
    @State private var looks = 0
    @State private var isLooking = false
    /// What the last look found, while its question or its answer is shown.
    @State private var found: LeftTheTrash?

    static let title: LocalizedStringResource = "Forget What Left the Trash…"

    var body: some View {
        BusyShown(isBusy: isLooking) { isShown in
            Button(String(localized: Self.title), systemImage: "eraser") {
                looks += 1
            }
            .symbolEffect(.pulse, options: .repeat(.continuous), isActive: isShown && !reduceMotion)
            .help(history.holdingReason.map { Text(verbatim: $0.explanation) } ?? Text(Self.title))
            .disabled(
                isLooking || !history.hasLoaded || history.batches.isEmpty || history.isRestoring || !history.mayMove
            )
        }
        .task(id: looks) {
            guard looks > 0 else { return }
            isLooking = true
            let found = await history.whatLeftTheTrash()
            isLooking = false
            // A look the page has left asks nothing.
            guard !Task.isCancelled else { return }
            self.found = found
        }
        .confirmationDialog(
            Text(verbatim: found.flatMap { Self.question(for: $0) } ?? ""),
            isPresented: Binding(
                get: { found.flatMap { Self.question(for: $0) } != nil }, set: { if !$0 { found = nil } }
            ),
            presenting: found
        ) { found in
            Button("Forget", role: .destructive) {
                Task { await history.forgetWhatLeftTheTrash(found) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("History stops listing what has already left the Trash, so nothing on your Mac changes.")
        }
        .alert(
            Text("Peel found nothing in History that has left the Trash"),
            isPresented: Binding(get: { found?.records.isEmpty == true }, set: { if !$0 { found = nil } })
        ) {
            Button("OK") {}
        }
    }

    /// The question for what a look found, or nil when nothing has left the Trash.
    static func question(for found: LeftTheTrash) -> String? {
        guard !found.records.isEmpty else { return nil }
        // An alert's title is drawn as plain text, which leaves inflection markup as written.
        return String(inflecting: "Forget ^[\(found.records.count) item](inflect: true) in ^[\(found.removals) removal](inflect: true)?")
    }
}
