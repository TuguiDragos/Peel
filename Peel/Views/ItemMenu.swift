import AppKit
import PeelCore
import SwiftUI

/// The Control-click menu of a row for one file, folder, or app Peel can move, the same on every page.
///
/// Excluding adds the item to the list Settings keeps, where it can be removed again, and every tool stops
/// offering it. An app is added by its identifier, as Settings does, so it stays excluded wherever it moves.
/// Excluding is off while the list can't be read, since adding to it then would start it over and drop what
/// it held, and for anything Settings refuses as too broad.
struct ItemMenu: View {
    let url: URL
    /// The identifier of the app itself, when the row is one.
    var appIdentifier: String?
    var isExcluded = false
    /// Opens the row's note, which a keyboard or VoiceOver reaches here, since its button in the row takes no
    /// keyboard focus.
    var showNote: (() -> Void)?

    var body: some View {
        if let showNote {
            Button("Show Note", systemImage: "info.circle", action: showNote)
            Divider()
        }
        Button("Show in Finder", systemImage: "folder") {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
        Button("Copy Path", systemImage: "doc.on.doc") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(url.path(percentEncoded: false), forType: .string)
        }
        Divider()
        Button("Exclude from Peel", systemImage: "hand.raised") {
            Task {
                if let appIdentifier {
                    await ExclusionsStore.shared.add(bundleIdentifier: appIdentifier)
                } else {
                    await ExclusionsStore.shared.add(paths: [url])
                }
            }
        }
        .disabled(isExcluded || ExclusionsStore.shared.exclusions.isUnreadable || (appIdentifier == nil && ExclusionsStore.isTooBroad(url)))
    }
}
