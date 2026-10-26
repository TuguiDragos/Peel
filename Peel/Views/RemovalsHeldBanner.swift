import PeelCore
import SwiftUI

/// What keeps Peel from moving anything at all: the exclusions or History can't be read, or History can't be written.
/// Exclusions not read yet are none of these, since they are read as Peel starts.
enum MovesHeld: Equatable {
    case exclusionsUnreadable
    case historyUnreadable
    case historyUnwritable

    static func reason(
        exclusionsUnreadable: Bool, historyUnreadable: Bool, historyUnwritable: Bool, recordsInHistory: Bool = true
    ) -> MovesHeld? {
        if exclusionsUnreadable { return .exclusionsUnreadable }
        guard recordsInHistory else { return nil }
        if historyUnreadable { return .historyUnreadable }
        return historyUnwritable ? .historyUnwritable : nil
    }

    @MainActor
    static func reason(
        exclusions: ExclusionsStore, history: RemovalHistoryStore, recordsInHistory: Bool = true
    ) -> MovesHeld? {
        reason(
            exclusionsUnreadable: exclusions.exclusions.isUnreadable, historyUnreadable: history.isUnreadable,
            historyUnwritable: history.cannotBeWritten, recordsInHistory: recordsInHistory
        )
    }
}

/// Over a page that can move something to the Trash or put it back, while `MovesHeld` names a reason: nothing moves
/// until it is gone, so the page's own button is off, and this says why. It shows only then.
struct RemovalsHeldBanner: View {
    @Environment(ExclusionsStore.self) private var exclusions
    @Environment(RemovalHistoryStore.self) private var history
    @Environment(\.openSettings) private var openSettings
    /// On History's own page, whose list says it with Start Over beside it, History is left unsaid here.
    var isOnHistoryPage = false
    /// False on a page whose action History doesn't record, which only the exclusions hold back.
    var recordsInHistory = true

    var body: some View {
        let held = MovesHeld.reason(exclusions: exclusions, history: history, recordsInHistory: recordsInHistory)
        if held == .exclusionsUnreadable {
            Notice(
                title: Text("Peel couldn’t read your exclusions"),
                detail: Text("Peel removes nothing and puts nothing back until you start the list over in Settings.")
            ) {
                Button("Open Peel Settings") { SettingsPane.exclusions.open(with: openSettings) }
            }
            .padding(.vertical, 6)
            .listRowSeparator(.hidden)
        } else if held == .historyUnreadable, !isOnHistoryPage {
            Notice(
                title: Text("Peel couldn’t read History"),
                detail: Text("Peel removes nothing until you start History over, so that everything it moves can be put back.")
            ) {
                Button("Open History") {
                    Navigator.shared.requestedTool = .history
                }
            }
            .padding(.vertical, 6)
            .listRowSeparator(.hidden)
        } else if held == .historyUnwritable {
            Notice(
                title: Text("Peel can’t write History"),
                detail: Text("The disk is full, or Peel’s folder can’t be written. Peel removes nothing until it can, so that everything it moves can be put back.")
            ) {}
            .padding(.vertical, 6)
            .listRowSeparator(.hidden)
        }
    }
}
