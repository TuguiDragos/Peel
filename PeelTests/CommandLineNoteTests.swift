import Foundation
@testable import Peel
import Testing

@MainActor
struct CommandLineNoteTests {
    /// The note says what the row offers: nothing to run once `peel` is on the path, a line for the shell on an account
    /// that isn't an administrator's, the command when there is one, and no command when there is none.
    @Test func theNoteFollowsTheRow() {
        func note(installed: Bool = false, standard: Bool = false, offered: Bool = true) -> String {
            String(localized: GeneralSettingsView.commandLineNote(
                installed: installed, standardAccount: standard, offersACommand: offered
            ))
        }

        #expect(!note(installed: true).contains("Run the command"))
        #expect(note(installed: true).contains("on your path"))
        #expect(note(standard: true).contains("Add the line below"))
        #expect(note().contains("Run the command"))
        #expect(!note(offered: false).contains("Run the command"))
        #expect(note(offered: false).contains("says why there is no command"))
    }
}
