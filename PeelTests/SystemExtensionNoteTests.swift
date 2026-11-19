import Foundation
@testable import Peel
import Testing

@MainActor
struct SystemExtensionNoteTests {
    /// One note on macOS 26 and 27: how macOS removes the extensions and that Orphaned Files lists what the app left,
    /// with System Settings' step only where macOS 27 deletes a network extension there.
    @Test func everyNoteSaysHowMacOSRemovesThemAndWhatOrphanedFilesLists() {
        for isOne in [true, false] {
            for deletes in [true, false] {
                let said = SystemExtensionNotice.said(
                    names: "Example Extension", app: "Example", isOne: isOne, systemSettingsDeletesThem: deletes
                ).map { String(localized: $0) }
                #expect(said.count == (deletes ? 2 : 1))
                #expect(said.first?.contains("Orphaned Files then lists what the app left.") == true)
                #expect(said.last?.contains("Network Extensions") == deletes)
            }
        }
    }
}
