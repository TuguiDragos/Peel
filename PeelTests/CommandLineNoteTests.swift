import Foundation
@testable import Peel
import Testing

@MainActor
struct CommandLineNoteTests {
    /// The note says what the row offers: nothing to run once `peel` is on the path, a line for the shell on an account
    /// that isn't an administrator's, and the command otherwise.
    @Test func theNoteFollowsTheRow() {
        let installed = String(localized: GeneralSettingsView.commandLineNote(installed: true, standardAccount: false))
        let standard = String(localized: GeneralSettingsView.commandLineNote(installed: false, standardAccount: true))
        let toRun = String(localized: GeneralSettingsView.commandLineNote(installed: false, standardAccount: false))

        #expect(!installed.contains("Run the command"))
        #expect(installed.contains("on your path"))
        #expect(standard.contains("Add the line below"))
        #expect(toRun.contains("Run the command"))
    }
}
