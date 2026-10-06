import SwiftUI

extension View {
    /// Starts a list's scroll bar below the band of a section header held at the top of the list, as Finder's starts
    /// below its column headings. On macOS 27 it otherwise starts level with that band. `hasHeaders` is whether the
    /// list shows any section header at the moment. macOS 27 takes the margin only when the list is built, so the
    /// list is built again when its headers come or go.
    @ViewBuilder
    func scrollBarBelowSectionHeaders(_ hasHeaders: Bool = true) -> some View {
        if #available(macOS 27, *) {
            contentMargins(.top, hasHeaders ? sectionHeaderBand : 0, for: .scrollIndicators)
                .id(hasHeaders)
        } else {
            self
        }
    }
}

/// The height of the row AppKit draws for a list's section header.
private let sectionHeaderBand: CGFloat = 28
