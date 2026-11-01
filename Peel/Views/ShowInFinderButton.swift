import AppKit
import SwiftUI

/// Shows an item in Finder: Finder's own symbol at the end of the row that says where the item is.
struct ShowInFinderButton: View {
    let url: URL

    var body: some View {
        RowSymbolButton("Show in Finder", systemImage: "finder") {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
        .help(Text("Show in Finder"))
    }
}

/// A symbol alone as a button at the end of a row, which VoiceOver names by its title. The target reaches past the
/// symbol to the 20 points the HIG asks for and gives them back outside, so the row keeps its height and the symbol
/// stands at the row's edge.
struct RowSymbolButton: View {
    let title: LocalizedStringKey
    let systemImage: String
    let action: () -> Void

    init(_ title: LocalizedStringKey, systemImage: String, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .padding(3)
                .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .padding(-3)
    }
}
