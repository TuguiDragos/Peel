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
        #expect(group.movable(canUseHelper: true) == SizeTotal(known: 10, isComplete: true))
    }

    @Test func whatOnlyTheHelperMovesCountsOnlyWhileItCanAct() {
        let cache = OrphanItem(
            url: URL(filePath: "/Users/x/Library/Caches/org.example.gone"), kind: .caches, size: 10,
            modificationDate: nil, requiresPrivileges: false
        )
        let daemon = OrphanItem(
            url: URL(filePath: "/Library/LaunchDaemons/org.example.gone.plist"), kind: .launchDaemons, size: 5,
            modificationDate: nil, requiresPrivileges: true
        )
        let group = OrphanGroup(identifier: "org.example.gone", items: [cache, daemon])
        let tool = PackageReceipt.Item(url: URL(filePath: "/usr/local/bin/org.example.tool"), size: 500, requiresPrivileges: true)
        let app = PackageReceipt.Item(url: URL(filePath: "/Applications/Example.app"), size: 20, requiresPrivileges: false)
        let receipt = PackageReceipt(
            identifier: "org.example.pkg", version: nil, installDate: nil, volume: URL(filePath: "/"), items: [tool, app]
        )
        var installer = InstallerItem(
            url: URL(filePath: "/Library/Updates/Example.pkg"), kind: .appInstaller, name: "Example.pkg", size: 300, date: nil,
            installedApp: nil, isReadOnly: false, notes: []
        )
        installer.requiresPrivileges = true
        let download = InstallerItem(
            url: URL(filePath: "/Users/x/Downloads/Example.dmg"), kind: .appInstaller, name: "Example.dmg", size: 40,
            date: nil, installedApp: nil, isReadOnly: false, notes: []
        )

        #expect(group.movable(canUseHelper: false) == SizeTotal(known: 10, isComplete: true))
        #expect(group.movable(canUseHelper: true) == SizeTotal(known: 15, isComplete: true))
        #expect(receipt.movable(canUseHelper: false) == SizeTotal(known: 20, isComplete: true))
        #expect(receipt.movable(canUseHelper: true) == SizeTotal(known: 520, isComplete: true))
        #expect([installer, download].movable(canUseHelper: false) == SizeTotal(known: 40, isComplete: true))
        #expect([installer, download].movable(canUseHelper: true) == SizeTotal(known: 340, isComplete: true))
    }

    @Test func anOrphanGroupKnowsWhyNothingInItCanMove() {
        let item = { (name: String, heldBack: HoldBack?) in
            var item = OrphanItem(
                url: URL(filePath: "/Users/x/Library/Containers/\(name)"), kind: .containers, size: 10,
                modificationDate: nil, requiresPrivileges: false
            )
            item.heldBack = heldBack
            return item
        }
        let group = { (items: [OrphanItem]) in OrphanGroup(identifier: "org.example.gone", items: items) }
        let documents = group([item("org.example.gone", .holdsDocuments), item("org.example.gone.share", .holdsDocuments)])
        let mixed = group([item("org.example.gone", .holdsDocuments), item("org.example.gone.share", .holdsALibrary)])
        let oneMoves = group([item("org.example.gone", .holdsDocuments), item("org.example.gone.share", .notMeasured)])

        #expect(documents.isLeftAlone && documents.sharedReason == .holdsDocuments)
        #expect(mixed.isLeftAlone && mixed.sharedReason == nil)
        #expect(!oneMoves.isLeftAlone && oneMoves.sharedReason == nil)
    }

    @Test func aReceiptCountsOnlyWhatCanMove() {
        var tool = PackageReceipt.Item(
            url: URL(filePath: "/usr/local/bin/org.example.tool"), size: 500, requiresPrivileges: true
        )
        tool.refusal = .protectedLocation
        let app = PackageReceipt.Item(
            url: URL(filePath: "/Applications/Example.app"), size: 20, requiresPrivileges: false
        )
        var receipt = PackageReceipt(
            identifier: "org.example.pkg", version: nil, installDate: nil, volume: URL(filePath: "/"), items: [tool, app]
        )

        #expect(receipt.movable(canUseHelper: true) == SizeTotal(known: 20, isComplete: true))
        receipt.isFileListKnown = false
        #expect(receipt.movable(canUseHelper: true) == SizeTotal(known: 0, isComplete: false))
    }
}
