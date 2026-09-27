import PeelCore
import SwiftUI

/// Over a page that can move something to the Trash or put it back, while the exclusions or History can't be
/// read: nothing moves until they can, so the page's own button is off, and this says why. It shows only then.
struct RemovalsHeldBanner: View {
    @Environment(ExclusionsStore.self) private var exclusions
    @Environment(RemovalHistoryStore.self) private var history
    /// On History's own page, whose list says it with Start Over beside it, History is left unsaid here.
    var isOnHistoryPage = false

    var body: some View {
        if exclusions.exclusions.isUnreadable {
            Notice(
                title: Text("Peel couldn’t read your exclusions"),
                detail: Text("Peel removes nothing and puts nothing back until you start the list over in Settings.")
            ) {
                SettingsLink {
                    Text("Open Peel Settings")
                }
            }
            .padding(.vertical, 6)
            .listRowSeparator(.hidden)
        } else if history.isUnreadable, !isOnHistoryPage {
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
        }
    }
}
