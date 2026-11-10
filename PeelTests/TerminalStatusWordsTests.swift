import Foundation
@testable import Peel
import Testing

struct TerminalStatusWordsTests {
    /// Each says why the tab's switches are off and what comes next, not only what went wrong.
    @Test func eachLabelSaysWhatFollowsAndWhatToDo() {
        #expect(TerminalPage.didNotAnswer("zsh").key.hasSuffix("Peel asks again when you open this page or come back to Peel."))
        #expect(GitTab.settingsUnreadable.key.contains("git config --global --list"))
        #expect(TerminalPage.profilesUnreadable.key.hasSuffix("Peel reads them again when you open this page or come back to Peel."))
    }
}
