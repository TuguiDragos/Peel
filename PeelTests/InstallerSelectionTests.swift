import Foundation
@testable import Peel
@testable import PeelCore
import Testing

@MainActor
struct InstallerSelectionTests {
    @Test func takesWhatWaitsForTheHelperOutOfTheSelection() {
        let macOS = URL(filePath: "/Applications/Install macOS Tahoe.app", directoryHint: .isDirectory)
        let image = URL(filePath: "/Users/me/Downloads/Tool.dmg")
        var installer = InstallerItem(
            url: macOS, kind: .macOSInstaller, name: "Install macOS Tahoe", size: 10, date: nil, installedApp: nil,
            isReadOnly: false, notes: []
        )
        installer.requiresPrivileges = true
        let download = InstallerItem(
            url: image, kind: .appInstaller, name: "Tool.dmg", size: 10, date: nil, installedApp: nil,
            isReadOnly: false, notes: []
        )

        let items = [installer, download]
        #expect(InstallerLibrary.selection([macOS, image], in: items, canUseHelper: false) == [image])
        #expect(InstallerLibrary.selection([macOS, image], in: items, canUseHelper: true) == [macOS, image])
    }
}
