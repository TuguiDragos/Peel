@testable import PeelCore
import Testing

struct MissingPermissionsNoticeTests {
    @Test func aHelperThatIsInstalledButNotAnsweringIsRepairedNotSetUp() {
        #expect(MissingPermissionsNotice(helper: .notAnswering, othersMissing: false) == .repairTheHelper)
        #expect(MissingPermissionsNotice(helper: .notAnswering, othersMissing: true) == .setUpAndRepairTheHelper)
    }

    @Test func whatIsNotThereIsSetUp() {
        for helper in [PrivilegedHelper.Standing.ready, .notInstalled, .waitingForApproval, .notThisAccount] {
            #expect(MissingPermissionsNotice(helper: helper, othersMissing: true) == .setUp)
            #expect(MissingPermissionsNotice(helper: helper, othersMissing: false) == .setUp)
        }
    }

    /// The helper another copy of Peel installed has no Install button here, so the banner says to open that copy.
    @Test func aHelperOfAnotherCopyIsNotSetUpBelow() {
        #expect(
            MissingPermissionsNotice(helper: .notInstalled, othersMissing: false, helperBelongsToAnotherCopy: true)
                == .helperOfAnotherCopy
        )
        #expect(
            MissingPermissionsNotice(helper: .notInstalled, othersMissing: true, helperBelongsToAnotherCopy: true)
                == .setUpWithHelperOfAnotherCopy
        )
        #expect(
            MissingPermissionsNotice(helper: .notInstalled, othersMissing: false, helperBelongsToAnotherCopy: false)
                == .setUp
        )
    }
}
