import PeelCore
import SwiftUI

/// Over a page that can move something to the Trash or put it back, while the exclusions can't be read: the
/// guard moves nothing until they can, so the page's own button is off, and this says why. It shows only then.
struct ExclusionsUnreadableBanner: View {
    @Environment(ExclusionsStore.self) private var exclusions

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
        }
    }
}
