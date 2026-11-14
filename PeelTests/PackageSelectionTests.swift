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

    @Test func anAppInsideAFolderThatGoesIsAskedToQuitAndLeavesTheDock() {
        let vendor = URL(filePath: "/Applications/Vendor", directoryHint: .isDirectory)
        let tool = InstalledApp(url: vendor.appending(path: "Tool.app"), bundleIdentifier: "org.example.tool", name: "Tool")
        var receipt = PackageReceipt(
            identifier: "org.example.pkg", version: nil, installDate: nil, volume: URL(filePath: "/"),
            items: [PackageReceipt.Item(url: vendor, size: 10, requiresPrivileges: false)]
        )
        receipt.apps = [tool]
        let trashed = URL(filePath: "/Users/example/.Trash/Vendor", directoryHint: .isDirectory)
        let result = TrashResult(trashed: [TrashedItem(originalURL: vendor, trashedURL: trashed, date: .now)])

        #expect(receipt.apps(in: [vendor]).map(\.name) == ["Tool"])
        #expect(receipt.apps(in: [URL(filePath: "/Applications/Other")]).isEmpty)
        #expect(PackageLibrary.appsThatMoved(in: result, among: [tool]) == [tool.url: trashed.appending(path: "Tool.app")])
    }
}
