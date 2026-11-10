import Foundation
@testable import Peel
import Testing

struct ShellTurnAllOffTests {
    /// Turn All Off empties only Peel's own file, so what the person's .zshrc sets still applies.
    @Test func theQuestionDoesNotPromiseMacOSsPrompt() {
        #expect(ShellTab.afterTurningAllOff.key == "New windows start with only what your own shell files and macOS set.")
    }
}
