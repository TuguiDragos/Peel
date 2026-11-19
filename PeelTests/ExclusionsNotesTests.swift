import Foundation
@testable import Peel
import Testing

@MainActor
struct ExclusionsNotesTests {
    /// An exclusion keeps Peel from putting anything back there, and keeps Homebrew from upgrading a package, which
    /// the notes have to say before someone finds out at Put Back or Upgrade.
    @Test func theNotesSayWhatAnExclusionStops() {
        let files = String(localized: ExclusionsSettingsView.filesAndFoldersNote)
        let apps = String(localized: ExclusionsSettingsView.appsNote)

        #expect(files.contains("never puts anything back into them"))
        #expect(files.contains("Homebrew still list what is inside, but leave it alone"))
        #expect(apps.contains("puts back an excluded app"))
        #expect(apps.contains("add them to Files and Folders above"))
    }

    @Test func theTabSaysHowManyEntriesItCouldntRead() {
        #expect(ExclusionsSettingsView.unreadableEntriesNote(0) == nil)
        #expect(ExclusionsSettingsView.unreadableEntriesNote(1) == "Peel could not read 1 entry of the saved list, so it does not protect what is written there. Add what you need again below.")
        #expect(ExclusionsSettingsView.unreadableEntriesNote(4)?.contains("4 entries of the saved list") == true)
    }
}
