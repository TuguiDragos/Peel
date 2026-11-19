import Foundation
@testable import Peel
import Testing

struct TerminalStatusWordsTests {
    @Test func eachStateIsShortAndItsNoteSaysWhatFollowsAndWhatToDo() {
        #expect(TerminalPage.didNotAnswer("zsh").key == "%@ did not answer")
        #expect(TerminalPage.offUntilItAnswers.key.hasSuffix("Peel asks again when you open this page or come back to Peel."))
        #expect(GitTab.settingsUnreadable.key == "Git could not read your settings")
        #expect(GitTab.settingsUnreadableNote.key.contains("git config --global --list"))
        #expect(TerminalPage.profilesUnreadable.key == "Peel could not read the Terminal profiles")
        #expect(TerminalPage.profilesUnreadableNote.key.hasSuffix("reads them again when you open this page or come back to Peel."))
        #expect(ToolsTab.unrunnableBrew.key == "The `brew` you chose cannot run now")
        #expect(ToolsTab.unrunnableBrewNote.key == "Peel runs only the `brew` you chose, so it runs none until that one can run or you choose another.")
    }

    @Test func theBarsSayWherePeelKeepsTheseSettings() {
        #expect(GitTab.turningOneOff.key == "Peel changes these with `git config --global`. Turning one off puts back what was there before Peel, or removes it when you had set it yourself.")
        #expect(ShellTab.whereTheyAreKept.key == "Peel keeps these in a file of its own, not in your shell files.")
        #expect(SSHTab.whereTheyAreKept.key == "Peel keeps these in a file of its own, not in your ~/.ssh/config.")
    }
}
