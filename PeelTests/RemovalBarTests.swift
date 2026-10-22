import Foundation
@testable import Peel
import PeelCore
import Testing

@MainActor
struct RemovalBarTests {
    private func parts(_ count: Int) -> [CarriedSelection.Part] {
        (1...count).map { index in
            CarriedSelection.Part(
                page: CarriedSelection.Page(tool: "orphans", scope: "org.example.gone\(index)"),
                title: "org.example.gone\(index)", source: "org.example.gone\(index)", sourceKey: nil,
                sizes: [URL(filePath: "/Users/me/Library/Caches/org.example.gone\(index)"): 4_096]
            )
        }
    }

    @Test func listsTheFirstPagesOfALongSelectionAndCountsTheItemsOfTheRest() {
        let lines = RemovalBar.lines(for: parts(80))
        let most = RemovalFailureAlert.mostListed
        #expect(lines.count == most + 1)
        for (index, line) in lines.prefix(most).enumerated() {
            #expect(line.hasPrefix("org.example.gone\(index + 1):"), "\(line)")
        }
        #expect(lines.last?.contains("76") == true, "\(lines.last ?? "")")
        #expect(RemovalBar.lines(for: parts(most)).count == most)
    }
}
