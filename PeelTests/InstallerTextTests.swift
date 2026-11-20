import Foundation
@testable import Peel
import PeelCore
import Testing

struct InstallerTextTests {
    @Test func aFirmwareRowShowsItsFileFirstAndItsFolderUnderIt() throws {
        let folder = URL.homeDirectory.appending(path: "Library/Group Containers/K36BKF7T3D.group.com.apple.configurator/Library/Caches/Firmware", directoryHint: .isDirectory)
        let file = folder.appending(path: "iPhone17,1_26.1_23B85_Restore.ipsw")

        let shown = try #require(InstallerDetailView.shownPath(of: file, kind: .firmware))
        #expect(shown.name == "iPhone17,1_26.1_23B85_Restore.ipsw")
        #expect(shown.folder == "~/Library/Group Containers/K36BKF7T3D.group.com.apple.configurator/Library/Caches/Firmware")
        #expect(InstallerDetailView.shownPath(of: file, kind: .appInstaller) == nil)
    }

    @Test func eachKindSaysWhatItIsInAFewWords() {
        #expect(InstallerItem.Kind.appInstaller.explanation.key == "Disk images, packages, and archives holding an app or an installer, in Downloads and the other places installers are usually left. A disk image can also be one you made to keep files in.")
        #expect(InstallerItem.Kind.firmware.explanation.key == "Firmware for restoring an iPhone, an iPad, or a Mac, downloaded again when a device needs it.")
        #expect(InstallerItem.Kind.incompleteDownload.explanation.key == "Downloads that never finished, still named .crdownload, .part, or .download.")
        #expect(InstallerItem.Kind.updateDownload.explanation.key == "Updates an app downloaded and keeps until it installs them. If one is gone, the app downloads it again.")
    }

    @Test func theBackupsSayWhyPeelLeavesThemAndWhereTheyGo() {
        #expect(InstallerDetailView.deleteBackupNote.key == "What is inside came off a device and may be the only copy. Delete a backup in System Settings > General > Storage > iOS Files.")
    }
}
