import Foundation
@testable import Peel
import PeelCore
import Testing

struct RemovalOutcomeTests {
    @Test func tellsOfShellFilesThatStillNameWhatMoved() {
        let outcome = RemovalOutcome()
        let reference = ShellReferences.Reference(file: URL(filePath: "/Users/me/.zshrc"), line: 12)

        outcome.report(TrashResult(), shellReferences: [reference])
        #expect(!outcome.isEmpty && outcome.shellReferences == [reference])
        outcome.report(TrashResult())
        #expect(outcome.shellReferences == [reference], "a removal with nothing to tell changes nothing")

        outcome.clear()
        #expect(outcome.isEmpty)
    }
}
