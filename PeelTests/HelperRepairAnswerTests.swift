import Foundation
@testable import Peel
import PeelCore
import Testing

@MainActor
struct HelperRepairAnswerTests {
    private struct NotPermitted: LocalizedError {
        var errorDescription: String? { "Operation not permitted" }
    }

    private final class Seen {
        var spoken: [AttributedString] = []
        var loginItemsOpened = 0
    }

    private func helper(
        after status: PrivilegedHelper.Status, isResponding: Bool? = nil,
        approval: PrivilegedHelper.ChangeApproval = .approved, seen: Seen
    ) -> HelperModel {
        HelperModel(
            performing: { _ in throw NotPermitted() },
            announcing: { seen.spoken.append($0) },
            status: .enabled,
            reading: {
                HelperModel.Reading(
                    status: status, isAdministrator: false, isResponding: isResponding,
                    isRegisteredByAnotherCopy: false
                )
            },
            approving: { approval },
            openingLoginItems: { seen.loginItemsOpened += 1 }
        )
    }

    @Test func aRepairThatWaitsForApprovalIsNoFailure() async {
        let seen = Seen()
        let helper = helper(after: .requiresApproval, seen: seen)

        let failure = await helper.repair()

        #expect(failure == nil)
        #expect(seen.loginItemsOpened == 1)
        let state = String(localized: "\(String(localized: "Helper")): \(String(localized: helper.stateWords))")
        #expect(seen.spoken.map { String($0.characters) } == [state])
        #expect(helper.standing == .waitingForApproval)
    }

    @Test func aRepairAfterWhichTheHelperAnswersIsNoFailure() async {
        let seen = Seen()
        let helper = helper(after: .enabled, isResponding: true, seen: seen)

        #expect(await helper.repair() == nil)
        #expect(seen.loginItemsOpened == 0)
    }

    @Test func aRepairThatLeavesTheHelperAsItWasSaysWhy() async {
        for (status, isResponding) in [(PrivilegedHelper.Status.enabled, false as Bool?), (.notRegistered, nil)] {
            let seen = Seen()
            let helper = helper(after: status, isResponding: isResponding, seen: seen)

            let failure = await helper.repair()

            #expect(failure?.action == .repair, "\(status)")
            #expect(failure?.reason == "Operation not permitted", "\(status)")
            #expect(seen.spoken.isEmpty, "\(status)")
            #expect(seen.loginItemsOpened == 0, "\(status)")
        }
    }

    @Test func aRepairNobodyApprovedOpensNothing() async {
        for approval in [PrivilegedHelper.ChangeApproval.canceled, .refused] {
            let seen = Seen()
            let helper = helper(after: .requiresApproval, approval: approval, seen: seen)

            let failure = await helper.repair()

            #expect((failure == nil) == (approval == .canceled))
            #expect(seen.loginItemsOpened == 0)
        }
    }

    @Test func anInstallThatWaitsForApprovalOpensLoginItemsOnce() async {
        let seen = Seen()
        let helper = helper(after: .requiresApproval, seen: seen)

        #expect(await helper.install() == nil)
        #expect(seen.loginItemsOpened == 1)
    }
}
