import SwiftUI

extension View {
    /// Starts a list's scroll bar below the band of a section header held at the top of the list, as Finder's starts
    /// below its column headings. On macOS 27 it otherwise starts level with that band. `isOn` says whether the list
    /// has that band. macOS 27 takes the margin only when the list is built, so the list is built again when `isOn`
    /// changes, which sends it back to its top and takes the focus from the search field above it. So `isOn` follows
    /// what the page found, never what a search leaves of it.
    @ViewBuilder
    func scrollBarBelowSectionHeaders(_ isOn: Bool = true) -> some View {
        if #available(macOS 27, *) {
            contentMargins(.top, isOn ? sectionHeaderBand : 0, for: .scrollIndicators)
                .id(isOn)
        } else {
            self
        }
    }
}

/// The height of the row AppKit draws for a list's section header.
private let sectionHeaderBand: CGFloat = 28
