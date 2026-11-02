import Foundation
@testable import Peel
@testable import PeelCore
import Testing

struct OrphanNothingMovesTests {
    private func item(_ name: String, _ heldBack: HoldBack?) -> OrphanItem {
        var item = OrphanItem(
            url: URL(filePath: "/Users/x/Library/Containers/\(name)"), kind: .containers, size: 10,
            modificationDate: nil, requiresPrivileges: false
        )
        item.heldBack = heldBack
        return item
    }

    @Test func aGroupWhereNothingMovesSaysWhyAtItsHead() {
        let documents = OrphanGroup(
            identifier: "org.example.gone",
            items: [item("org.example.gone", .holdsDocuments), item("org.example.gone.share", .holdsDocuments)]
        )
        let mixed = OrphanGroup(
            identifier: "org.example.gone",
            items: [item("org.example.gone", .holdsDocuments), item("org.example.gone.share", .holdsALibrary)]
        )
        let oneMoves = OrphanGroup(identifier: "org.example.gone", items: [item("org.example.gone", nil)])

        let documentsReason = String(localized: HoldBack.holdsDocuments.explanation)
        #expect(OrphanDetailView.whyNothingMoves(in: documents) == documentsReason)
        #expect(OrphanDetailView.whyNothingMoves(in: mixed) == String(localized: "Nothing here can be moved. Each file’s note says why."))
        #expect(OrphanDetailView.whyNothingMoves(in: oneMoves) == nil)
    }
}
