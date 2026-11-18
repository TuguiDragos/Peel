import Foundation
@testable import Peel
import PeelCore
import Testing

struct ReasonsSayTheStepTests {
    /// A reason that stops at what happened leaves the person without the next step, so each says it.
    @Test func eachReasonEndsWithWhatToDo() {
        let notPermitted = String(localized: "macOS did not allow it and did not say why. Home shows which permissions Peel is missing.")
        let needsHelper = String(localized: "It needs administrator access, which the Peel helper provides. Home says what the helper needs.")

        #expect(TrashFailure.Reason.lastCopy.explanation == String(localized: "The copy Peel was keeping has changed or moved since the scan, so this one may be the last, and Peel left it. Scan again to review it."))
        #expect(TrashFailure.Reason.notPermitted.explanation == notPermitted)
        #expect(RestoreFailure.notPermitted.explanation == notPermitted)
        #expect(TrashFailure.Reason.needsHelper.explanation == needsHelper)
        #expect(RestoreFailure.needsHelper.explanation == needsHelper)
    }

    @Test func theLinkAndTwoFileReasonsSayWhy() {
        let target = "/Applications/Example.app"

        #expect(TrashFailure.Reason.stillLeadsTo(target).explanation == String(localized: "It is a link that still leads to \(URL(filePath: target).abbreviatedPath), and from this folder the Peel helper removes only links that lead nowhere."))
        #expect(FixedSentence.translated("It still leads to something on this Mac.") == String(localized: "It is a link that still leads to something on this Mac, and from that folder the Peel helper removes only links that lead nowhere."))
        #expect(FixedSentence.translated("Two files declare this job.") == String(localized: "Two files in /Library/LaunchDaemons declare this job, so the Peel helper cannot tell which one to load. Move one of them to the Trash first."))
    }
}
