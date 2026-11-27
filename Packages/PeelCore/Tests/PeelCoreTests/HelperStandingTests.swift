@testable import PeelCore
import Testing

struct HelperStandingTests {
    @MainActor @Test func readsTheStatusAwayFromTheMainActor() async {
        final class Turn {
            var taken = false
        }
        let turn = Turn()
        Task { @MainActor in turn.taken = true }

        _ = await PrivilegedHelper.currentStatus()

        #expect(turn.taken)
    }

    @MainActor @Test func asksWhetherThisAccountIsAnAdministratorAwayFromTheMainActor() async {
        final class Turn {
            var taken = false
        }
        let turn = Turn()
        Task { @MainActor in turn.taken = true }

        _ = await PrivilegedHelper.isAdministratorNow()

        #expect(turn.taken)
    }

    @Test func aChangeRunsOnlyOnceApproved() async throws {
        for approval in [PrivilegedHelper.ChangeApproval.approved, .canceled, .refused] {
            var changed = false

            let answer = try await PrivilegedHelper.changeAsAnAdministrator({ changed = true }, approval: { approval })

            #expect(answer == approval)
            #expect(changed == (approval == .approved))
        }
    }

    @Test func anAdministratorIsNeverAsked() async {
        var asked = false

        let answer = await PrivilegedHelper.approvalToChange(isAdministrator: { true }) {
            asked = true
            return .refused
        }

        #expect(answer == .approved)
        #expect(!asked)
    }

    @Test func anotherAccountChangesTheHelperWithWhatAnAdministratorAnswers() async {
        for given in [PrivilegedHelper.ChangeApproval.approved, .canceled, .refused] {
            #expect(await PrivilegedHelper.approvalToChange(isAdministrator: { false }, ask: { given }) == given)
        }
    }

    @Test func everyAccountSeesWhatTheRegistrationSays() {
        func standing(_ status: PrivilegedHelper.Status, _ isResponding: Bool?) -> PrivilegedHelper.Standing {
            PrivilegedHelper.Standing(status: status, isResponding: isResponding)
        }
        #expect(standing(.enabled, true) == .ready)
        #expect(standing(.enabled, nil) == .ready)
        #expect(standing(.enabled, false) == .notAnswering)
        #expect(standing(.requiresApproval, nil) == .waitingForApproval)
        #expect(standing(.notRegistered, nil) == .notInstalled)
        #expect(standing(.unavailable, nil) == .notInstalled)
    }
}
