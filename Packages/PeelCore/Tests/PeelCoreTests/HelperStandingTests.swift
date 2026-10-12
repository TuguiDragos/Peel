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

        _ = await PrivilegedHelper.currentAvailability()

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

    /// The helper serves administrators only, so a standard account is never offered to install, approve or repair
    /// it, whatever its registration says.
    @Test func aStandardAccountNeedsAnAdministratorWhateverTheRegistration() {
        for status in statuses {
            for isResponding in [true, false, nil] as [Bool?] {
                let standing = PrivilegedHelper.Standing(
                    status: status, isAvailableToThisAccount: false, isResponding: isResponding
                )
                #expect(standing == .notThisAccount)
            }
        }
    }

    @Test func anAdministratorSeesWhatTheRegistrationSays() {
        func standing(_ status: PrivilegedHelper.Status, _ isResponding: Bool?) -> PrivilegedHelper.Standing {
            PrivilegedHelper.Standing(status: status, isAvailableToThisAccount: true, isResponding: isResponding)
        }
        #expect(standing(.enabled, true) == .ready)
        #expect(standing(.enabled, nil) == .ready)
        #expect(standing(.enabled, false) == .notAnswering)
        #expect(standing(.requiresApproval, nil) == .waitingForApproval)
        #expect(standing(.notRegistered, nil) == .notInstalled)
        #expect(standing(.unavailable, nil) == .notInstalled)
    }
}
