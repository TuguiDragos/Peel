import AppKit
import PeelCore
import SwiftUI

/// A notice for each folder a scan did not read whole, naming it, with a way to it in Finder.
struct SkippedFolderNotices: View {
    enum Subject {
        case app
        case apps
        case orphans
        /// A page that lists what is in the person's folders, such as Installers.
        case files
    }

    let crowded: [CrowdedFolder]
    let cutShort: [URL]
    let subject: Subject

    var body: some View {
        ForEach(crowded, id: \.url) { folder in
            Notice(
                title: Text("Peel did not look inside \(folder.url.abbreviatedPath)"), detail: detail(folder),
                kind: .note
            ) {
                showInFinder(folder.url)
            }
            .listRowSeparator(.hidden)
        }
        ForEach(cutShort, id: \.self) { url in
            Notice(
                title: Text("Peel looked inside only part of \(url.abbreviatedPath)"), detail: partDetail, kind: .note
            ) {
                showInFinder(url)
            }
            .listRowSeparator(.hidden)
        }
    }

    private func showInFinder(_ url: URL) -> some View {
        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }

    private func detail(_ folder: CrowdedFolder) -> Text {
        switch (subject, folder.entries) {
        case (.app, let entries?):
            Text("It holds \(entries) items, too many to read quickly. Everything listed here can still go to the Trash. Anything this app left inside it stays where it is.")
        case (.app, nil):
            Text("It holds too many items to read quickly. Everything listed here can still go to the Trash. Anything this app left inside it stays where it is.")
        case (.apps, let entries?):
            Text("It holds \(entries) items, too many to read quickly. Everything listed here can still go to the Trash. Anything these apps left inside it stays where it is.")
        case (.apps, nil):
            Text("It holds too many items to read quickly. Everything listed here can still go to the Trash. Anything these apps left inside it stays where it is.")
        case (.orphans, let entries?):
            Text("It holds \(entries) items, too many to read quickly. Everything listed here can still go to the Trash. An orphaned file inside it stays where it is.")
        case (.orphans, nil):
            Text("It holds too many items to read quickly. Everything listed here can still go to the Trash. An orphaned file inside it stays where it is.")
        case (.files, let entries?):
            Text("It holds \(entries) items, too many to read quickly. Nothing inside it is listed here.")
        case (.files, nil):
            Text("It holds too many items to read quickly. Nothing inside it is listed here.")
        }
    }

    private var partDetail: Text {
        switch subject {
        case .app:
            Text("It holds more folders than Peel looks through. Everything listed here can still go to the Trash. Anything this app left in the folders Peel skipped stays where it is.")
        case .apps:
            Text("It holds more folders than Peel looks through. Everything listed here can still go to the Trash. Anything these apps left in the folders Peel skipped stays where it is.")
        case .orphans:
            Text("It holds more folders than Peel looks through. Everything listed here can still go to the Trash. An orphaned file in the folders Peel skipped stays where it is.")
        case .files:
            Text("It holds more folders than Peel looks through. Nothing in the folders Peel skipped is listed here.")
        }
    }
}
