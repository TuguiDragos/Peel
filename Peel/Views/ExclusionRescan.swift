import SwiftUI

extension View {
    /// Scans again when the exclusions change, for a tool's page, whose findings its library keeps.
    ///
    /// A scan is filtered by the exclusions as they stand when it runs, so after a change an item just excluded
    /// is still listed, and one taken off the list is still missing. The store remembers which revision each
    /// tool's page last scanned under, because Settings takes the whole pane, and while it is open no tool's page
    /// is on screen to notice. Duplicates and File Search don't use this, since they scan only when the user asks.
    func rescanOnExclusionChange(_ page: String, _ rescan: @escaping () async -> Void) -> some View {
        modifier(ExclusionRescan(page: page, rescan: rescan))
    }

    /// Scans again when the exclusions change, for a page whose findings are made with it and go with it, such as
    /// an app's page: `scannedUnder` is the revision its last scan read, nil before its first, so a page made after a
    /// change scans once, under the exclusions as they are.
    func rescanOnExclusionChange(scannedUnder revision: Int?, _ rescan: @escaping () async -> Void) -> some View {
        modifier(PageExclusionRescan(scannedUnder: revision, rescan: rescan))
    }
}

private struct PageExclusionRescan: ViewModifier {
    @Environment(ExclusionsStore.self) private var exclusions
    let scannedUnder: Int?
    let rescan: () async -> Void

    func body(content: Content) -> some View {
        content.task(id: exclusions.revision) {
            guard let scannedUnder, scannedUnder != exclusions.revision else { return }
            await rescan()
        }
    }
}

private struct ExclusionRescan: ViewModifier {
    @Environment(ExclusionsStore.self) private var exclusions
    let page: String
    let rescan: () async -> Void

    func body(content: Content) -> some View {
        content.task(id: exclusions.revision) {
            guard exclusions.needsRescan(page) else { return }
            await rescan()
        }
    }
}
