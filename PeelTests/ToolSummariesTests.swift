import Foundation
@testable import Peel
import PeelCore
import Testing

struct ToolSummariesTests {
    @Test func spaceCountsItsAreasAndNeverAddsThemUp() {
        let looked = Looked(count: 9, size: SizeTotal(known: 180_000_000_000, isComplete: true))
        let areas = AttributedString(localized: "^[\(9) area](inflect: true)")

        #expect(Tool.space.figure(for: looked) == String(areas.characters))
        #expect(Tool.space.sentence(for: looked) == AttributedString(localized: "^[\(9) area](inflect: true)."))
        #expect(Tool.developer.figure(for: looked) == looked.size?.text, "a tool that adds up still shows its total")
    }
}
