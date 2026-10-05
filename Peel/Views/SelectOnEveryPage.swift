import PeelCore
import SwiftUI

/// The Select menu over every page a tool lists, in its toolbar. A page it selects on counts as seen, so Move to
/// Trash on any page moves what it selected there too: the person chose it, page by page or all at once.
struct SelectOnEveryPage: View {
    @Environment(SelectionCarrier.self) private var carrier
    let pages: SelectablePages<CarriedSelection.Page, URL>
    let selection: any RowSelection

    var body: some View {
        SelectMenu(
            pages: pages.selectablePageCount,
            list: pages.rows,
            selection: SeeingPages(selection: selection, pages: pages, carrier: carrier)
        )
    }
}

/// The menu reads as selected only what Move to Trash would move: a row on a page not seen yet stays where it is.
private final class SeeingPages: RowSelection {
    private let selection: any RowSelection
    private let pages: SelectablePages<CarriedSelection.Page, URL>
    private let carrier: SelectionCarrier

    init(selection: any RowSelection, pages: SelectablePages<CarriedSelection.Page, URL>, carrier: SelectionCarrier) {
        self.selection = selection
        self.pages = pages
        self.carrier = carrier
    }

    var selectedURLs: Set<URL> {
        get { pages.counted(selection.selectedURLs, seen: carrier.hasSeen) }
        set { select(newValue) }
    }

    func select(_ new: Set<URL>) {
        selection.select(new)
        for page in pages.pages(selectedIn: selection.selectedURLs) {
            carrier.saw(page)
        }
    }
}
