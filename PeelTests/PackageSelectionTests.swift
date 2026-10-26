import Foundation
@testable import Peel
@testable import PeelCore
import Testing

@MainActor
struct PackageSelectionTests {
    @Test func takesWhatWaitsForTheHelperOutOfTheSelection() {
        let daemon = URL(filePath: "/Library/LaunchDaemons/org.example.helper.plist")
        let support = URL(filePath: "/Users/Shared/Example/settings.plist")
        let receipt = PackageReceipt(
            identifier: "org.example.pkg", version: nil, installDate: nil, volume: URL(filePath: "/"),
            items: [
                PackageReceipt.Item(url: daemon, size: 10, requiresPrivileges: true),
                PackageReceipt.Item(url: support, size: 10, requiresPrivileges: false),
            ]
        )

        #expect(PackageLibrary.selection([daemon, support], in: [receipt], canUseHelper: false) == [support])
        #expect(PackageLibrary.selection([daemon, support], in: [receipt], canUseHelper: true) == [daemon, support])
    }
}
