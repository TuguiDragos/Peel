import Foundation
@testable import Peel
@testable import PeelCore
import Testing

struct ForgetReceiptQuestionTests {
    /// A package that left a tool or a driver, and no app, still loses its only list when its receipt goes.
    @Test func theQuestionGoesByWhatIsLeftOnDiskNotByTheApps() {
        let item = PackageReceipt.Item(url: URL(filePath: "/Library/Example/tool"), size: 1, requiresPrivileges: true)
        let leftATool = PackageReceipt(
            identifier: "org.example.pkg", version: nil, installDate: nil, volume: URL(filePath: "/"), items: [item]
        )
        var receiptOnly = PackageReceipt(
            identifier: "org.example.gone", version: nil, installDate: nil, volume: URL(filePath: "/"), items: []
        )
        receiptOnly.nothingLeftOnDisk = true

        #expect(ForgetReceiptDialog.returnKeepsTheReceipt(leftATool))
        #expect(ForgetReceiptDialog.message(for: leftATool).key.contains("Peel can no longer list what it put on this Mac"))
        #expect(!ForgetReceiptDialog.returnKeepsTheReceipt(receiptOnly))
        #expect(ForgetReceiptDialog.message(for: receiptOnly).key.contains("Nothing on it is left on this Mac"))
    }

    @Test func forgetAllSaysWhatStaysUntilTheHelperCanMoveIt() {
        let receipt = PackageReceipt(
            identifier: "org.example.solo", version: nil, installDate: nil, volume: URL.homeDirectory, items: []
        )
        let everything = ForgetReceiptsDialog.message(for: ForgetAll(receipts: [receipt], waitingForTheHelper: 0))
        let some = ForgetReceiptsDialog.message(for: ForgetAll(receipts: [receipt], waitingForTheHelper: 2))

        #expect(everything.contains("org.example.solo"))
        #expect(!everything.contains("helper"))
        #expect(some.hasPrefix(everything))
        #expect(some.contains("helper"))
    }

    @Test func asksToForgetOnlyOnceAMoveLeftNothingOfThePackage() {
        let item = PackageReceipt.Item(url: URL(filePath: "/Library/Example/tool"), size: 1, requiresPrivileges: false)
        let before = PackageReceipt(
            identifier: "org.example.pkg", version: nil, installDate: nil, volume: URL(filePath: "/"), items: [item]
        )
        var gone = PackageReceipt(
            identifier: "org.example.pkg", version: nil, installDate: nil, volume: URL(filePath: "/"), items: []
        )
        gone.nothingLeftOnDisk = true
        var other = PackageReceipt(
            identifier: "org.example.other", version: nil, installDate: nil, volume: URL(filePath: "/"), items: []
        )
        other.nothingLeftOnDisk = true

        #expect(PackageDetailView.toForgetNext(gone, after: before, mayForget: true)?.identifier == "org.example.pkg")
        #expect(PackageDetailView.toForgetNext(gone, after: before, mayForget: false) == nil)
        #expect(PackageDetailView.toForgetNext(before, after: before, mayForget: true) == nil)
        #expect(PackageDetailView.toForgetNext(other, after: before, mayForget: true) == nil)
        #expect(PackageDetailView.toForgetNext(nil, after: before, mayForget: true) == nil)
    }
}

