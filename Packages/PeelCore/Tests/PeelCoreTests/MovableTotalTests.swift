import Foundation
@testable import PeelCore
import Testing

/// A list shows what a page would move, so a row and the page it opens never give two figures for one thing.
struct MovableTotalTests {
    @Test func anOrphanGroupCountsOnlyWhatCanMove() {
        var library = OrphanItem(
            url: URL(filePath: "/Users/x/Pictures/org.example.gone"), kind: .elsewhere, size: 1_000,
            modificationDate: nil, requiresPrivileges: false
        )
        library.heldBack = .holdsALibrary
        let cache = OrphanItem(
            url: URL(filePath: "/Users/x/Library/Caches/org.example.gone"), kind: .caches, size: 10,
            modificationDate: nil, requiresPrivileges: false
        )
        let group = OrphanGroup(identifier: "org.example.gone", items: [library, cache])

        #expect(group.total == SizeTotal(known: 1_010, isComplete: true))
        #expect(group.movable == SizeTotal(known: 10, isComplete: true))
    }

    @Test func aReceiptCountsOnlyWhatCanMove() {
        var tool = PackageReceipt.Item(
            url: URL(filePath: "/usr/local/bin/org.example.tool"), size: 500, requiresPrivileges: true
        )
        tool.isLeftAlone = true
        let app = PackageReceipt.Item(
            url: URL(filePath: "/Applications/Example.app"), size: 20, requiresPrivileges: false
        )
        var receipt = PackageReceipt(
            identifier: "org.example.pkg", version: nil, installDate: nil, volume: URL(filePath: "/"), items: [tool, app]
        )

        #expect(receipt.movable == SizeTotal(known: 20, isComplete: true))
        receipt.isFileListKnown = false
        #expect(receipt.movable == SizeTotal(known: 0, isComplete: false))
    }
}
