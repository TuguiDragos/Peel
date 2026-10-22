import PeelCore
import SwiftUI

/// The Select menu over every page a tool lists, in its toolbar. A page it selects on counts as seen, so Move to
/// Trash on any page moves what it selected there too: the person chose it, page by page or all at once.
struct SelectOnEveryPage: View {
    @Environment(SelectionCarrier.self) private var carrier
    let pages: SelectablePages<CarriedSelection.Page, URL>
    let selection: any RowSelection
    var reading: (() async -> Bool)?
    var isDisabled = false
    /// Opens a page of the list when none with a bar is open, so what the menu selected shows, with Move to Trash.
    let open: (CarriedSelection.Page) -> Void

    var body: some View {
        SelectMenu(
            pages: pages.selectablePageCount,
            list: pages.rows,
            selection: SeeingPages(
                selection: selection, pages: pages, hasSeen: carrier.hasSeen, saw: carrier.saw, open: open
            ),
            reading: reading,
            isDisabled: isDisabled
        )
    }
}

/// The menu reads as selected only what Move to Trash would move: a row on a page not seen yet stays where it is.
final class SeeingPages: RowSelection {
    private let selection: any RowSelection
    private let pages: SelectablePages<CarriedSelection.Page, URL>
    private let hasSeen: (CarriedSelection.Page) -> Bool
    private let saw: (CarriedSelection.Page) -> Void
    private let open: (CarriedSelection.Page) -> Void

    init(
        selection: any RowSelection,
        pages: SelectablePages<CarriedSelection.Page, URL>,
        hasSeen: @escaping (CarriedSelection.Page) -> Bool,
        saw: @escaping (CarriedSelection.Page) -> Void,
        open: @escaping (CarriedSelection.Page) -> Void
    ) {
        self.selection = selection
        self.pages = pages
        self.hasSeen = hasSeen
        self.saw = saw
        self.open = open
    }

    var selectedURLs: Set<URL> {
        get { pages.counted(selection.selectedURLs, seen: hasSeen) }
        set { select(newValue) }
    }

    /// Selects `new`, counts every page it reaches as seen, and opens the first of them in the list's order.
    func select(_ new: Set<URL>) {
        selection.select(new)
        let selected = pages.pages(selectedIn: selection.selectedURLs)
        for page in selected {
            saw(page)
        }
        if let first = selected.first {
            open(first)
        }
    }
}
