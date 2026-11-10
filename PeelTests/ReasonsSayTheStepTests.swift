import Foundation
@testable import Peel
import PeelCore
import Testing

struct ReasonsSayTheStepTests {
    /// A reason that stops at what happened leaves the person without the next step, so each says it.
    @Test func eachReasonEndsWithWhatToDo() {
        let notPermitted = String(localized: "macOS didn’t allow it and didn’t say why. Home shows which permissions Peel is missing.")
        let needsHelper = String(localized: "It needs administrator access, which Peel’s helper provides. Home says what the helper needs.")

        #expect(TrashFailure.Reason.lastCopy.explanation == String(localized: "The copy Peel was keeping has changed or moved since the scan, so this one may be the last, and Peel left it. Scan again to review it."))
        #expect(TrashFailure.Reason.notPermitted.explanation == notPermitted)
        #expect(RestoreFailure.notPermitted.explanation == notPermitted)
        #expect(TrashFailure.Reason.needsHelper.explanation == needsHelper)
        #expect(RestoreFailure.needsHelper.explanation == needsHelper)
    }
}
