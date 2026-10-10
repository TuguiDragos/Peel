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
}
