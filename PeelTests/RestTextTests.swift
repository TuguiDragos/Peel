import Foundation
@testable import Peel
import Testing

struct RestTextTests {
    @Test func theDefaultAppNoteForFilesIsShort() {
        #expect(DefaultAppsSection.filesNote.key == "These kinds of files open with this app. Once it is gone, macOS opens each with the app Peel shows, and a kind under No app has nothing else to open it. Peel never changes which app opens what; you choose that in Finder, with Get Info.")
    }

    @Test func aDiskWithMacOSOrABackupSaysWhichFolderToChoose() {
        #expect(AppFoldersSection.systemOrBackup("/Volumes/Backup").key == "This disk holds a copy of macOS or a Time Machine backup, whose apps do not belong to this Mac. Choose the folder there that holds only your own apps.\n\n%@")
    }
}
