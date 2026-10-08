import Foundation
@testable import PeelCore
import ServiceManagement
import Testing

struct HelperRepairTests {
    private let alreadyRegistered = NSError(domain: SMAppServiceErrorDomain, code: Int(kSMErrorAlreadyRegistered))
    private let notAuthorized = NSError(domain: SMAppServiceErrorDomain, code: Int(kSMErrorAuthorizationFailure))
    private let notFound = NSError(domain: SMAppServiceErrorDomain, code: Int(kSMErrorJobNotFound))
    private let refused = NSError(domain: SMAppServiceErrorDomain, code: Int(EPERM))
    private let denied = NSError(domain: SMAppServiceErrorDomain, code: Int(kSMErrorLaunchDeniedByUser))

    /// A helper that could not be unregistered is still registered, so registering it again only says so: the reason
    /// the repair failed is what unregistering answered.
    @Test func aRepairThatCouldNotUnregisterTellsWhy() {
        let reason = PrivilegedHelper.repairFailure(registering: alreadyRegistered, afterUnregistering: notAuthorized)
        #expect((reason as NSError).code == Int(kSMErrorAuthorizationFailure))
    }

    @Test func anyOtherFailureToRegisterIsItsOwnReason() {
        let reason = PrivilegedHelper.repairFailure(registering: notAuthorized, afterUnregistering: notFound)
        #expect((reason as NSError).code == Int(kSMErrorAuthorizationFailure))
        let alone = PrivilegedHelper.repairFailure(registering: alreadyRegistered, afterUnregistering: nil)
        #expect((alone as NSError).code == Int(kSMErrorAlreadyRegistered))
    }

    @Test func aRefusalRightAfterUnregisteringIsTriedAgainAfterAPause() async throws {
        let registering = Registering(failures: [refused, refused])
        try await PrivilegedHelper.register(registering.attempt, status: { .notRegistered }, pause: registering.pause)
        #expect(registering.attempts == 3)
        #expect(registering.pauses == 2)
    }

    @Test func aRefusalThatLastsIsReportedAfterTheLastAttempt() async {
        let registering = Registering(failures: Array(repeating: refused, count: 10))
        await #expect(throws: refused) {
            try await PrivilegedHelper.register(
                registering.attempt, status: { .notRegistered }, pause: registering.pause
            )
        }
        #expect(registering.attempts == PrivilegedHelper.registrationAttempts)
        #expect(registering.pauses == PrivilegedHelper.registrationAttempts - 1)
    }

    @Test func anyOtherFailureIsReportedAtOnce() async {
        let registering = Registering(failures: [denied])
        await #expect(throws: denied) {
            try await PrivilegedHelper.register(
                registering.attempt, status: { .notRegistered }, pause: registering.pause
            )
        }
        #expect(registering.attempts == 1)
        #expect(registering.pauses == 0)
    }

    @Test func aRefusalOnceTheHelperWaitsForApprovalIsReportedAtOnce() async {
        let registering = Registering(failures: [refused])
        await #expect(throws: refused) {
            try await PrivilegedHelper.register(
                registering.attempt, status: { .requiresApproval }, pause: registering.pause
            )
        }
        #expect(registering.attempts == 1)
    }
}

private final class Registering: @unchecked Sendable {
    private var failures: [NSError]
    private(set) var attempts = 0
    private(set) var pauses = 0

    init(failures: [NSError]) {
        self.failures = failures
    }

    func attempt() throws {
        attempts += 1
        if !failures.isEmpty {
            throw failures.removeFirst()
        }
    }

    func pause() async throws {
        pauses += 1
    }
}
