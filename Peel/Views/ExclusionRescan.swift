import SwiftUI

extension View {
    /// Scans again when the exclusions change.
    ///
    /// A scan is filtered by the exclusions as they stand when it runs, so after a change an item just excluded
    /// is still listed, and one taken off the list is still missing. The store remembers which revision each
    /// page last scanned under, because Settings takes the whole pane, and while it is open no tool's page is on
    /// screen to notice. Duplicates and File Search don't use this, since they scan only when the user asks.
    func rescanOnExclusionChange(_ page: String, _ rescan: @escaping () async -> Void) -> some View {
        modifier(ExclusionRescan(page: page, rescan: rescan))
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
