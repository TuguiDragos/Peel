import Foundation
@testable import Peel
import PeelCore
import Testing

@MainActor
struct SelectOnEveryPageTests {
    private final class Rows: RowSelection {
        var selectedURLs: Set<URL> = []
        func select(_ selection: Set<URL>) { selectedURLs = selection }
    }

    @Test func opensTheFirstPageItSelectedOnInTheListsOrder() {
        let names = ["a", "b", "c"]
        let items = names.map { URL(filePath: "/Users/me/Library/Caches/org.example.\($0)") }
        let pages = names.map { CarriedSelection.Page(tool: "orphans", scope: "org.example.\($0)") }
        let selectable = SelectablePages(zip(pages, items).map { page, item in
            (page, SelectableRows(rows: [item], selectable: [item], recommended: []))
        })
        var opened: [CarriedSelection.Page] = []
        var seen: Set<CarriedSelection.Page> = []
        let seeing = SeeingPages(
            selection: Rows(), pages: selectable,
            hasSeen: { seen.contains($0) }, saw: { seen.insert($0) }, open: { opened.append($0) }
        )

        seeing.select([items[2], items[1]])
        #expect(opened == [pages[1]])
        #expect(seen == [pages[1], pages[2]])

        seeing.select([])
        #expect(opened == [pages[1]], "a selection of nothing opens nothing")
    }
}
