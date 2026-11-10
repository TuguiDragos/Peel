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
}
