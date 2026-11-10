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
        #expect(files.contains("won’t upgrade or uninstall it"))
        #expect(apps.contains("won’t put one back"))
        #expect(apps.contains("add them to Files and Folders above"))
    }
}
