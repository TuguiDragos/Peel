@testable import PeelCore
import Testing

struct HelperStandingTests {
    private let statuses: [PrivilegedHelper.Status] = [.notRegistered, .requiresApproval, .enabled, .unavailable]

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

    @Test func anAccountThatCantUseTheHelperNeverChangesIt() async throws {
        var changed = false

        let ran = try await PrivilegedHelper.changeAsAnAdministrator({ changed = true }, isAdministrator: { false })

        #expect(!ran)
        #expect(!changed)
    }

    @Test func anAdministratorChangesTheHelper() async throws {
        var changed = false

        let ran = try await PrivilegedHelper.changeAsAnAdministrator({ changed = true }, isAdministrator: { true })

        #expect(ran)
        #expect(changed)
    }

    @Test func aStandardAccountUsesAHelperThatWorksAndNeedsAnAdministratorForAnythingElse() {
        func standing(_ status: PrivilegedHelper.Status, _ isResponding: Bool?) -> PrivilegedHelper.Standing {
            PrivilegedHelper.Standing(status: status, isAdministrator: false, isResponding: isResponding)
        }
        #expect(standing(.enabled, true) == .ready)
        #expect(standing(.enabled, nil) == .ready)
        #expect(standing(.enabled, false) == .notThisAccount)
        for status in statuses where status != .enabled {
            for isResponding in [true, false, nil] as [Bool?] {
                #expect(standing(status, isResponding) == .notThisAccount)
            }
        }
    }

    @Test func anAdministratorSeesWhatTheRegistrationSays() {
        func standing(_ status: PrivilegedHelper.Status, _ isResponding: Bool?) -> PrivilegedHelper.Standing {
            PrivilegedHelper.Standing(status: status, isAdministrator: true, isResponding: isResponding)
        }
        #expect(standing(.enabled, true) == .ready)
        #expect(standing(.enabled, nil) == .ready)
        #expect(standing(.enabled, false) == .notAnswering)
        #expect(standing(.requiresApproval, nil) == .waitingForApproval)
        #expect(standing(.notRegistered, nil) == .notInstalled)
        #expect(standing(.unavailable, nil) == .notInstalled)
    }
}
