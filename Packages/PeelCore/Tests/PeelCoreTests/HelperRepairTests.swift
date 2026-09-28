import Foundation
@testable import PeelCore
import ServiceManagement
import Testing

struct HelperRepairTests {
    private let alreadyRegistered = NSError(domain: SMAppServiceErrorDomain, code: Int(kSMErrorAlreadyRegistered))
    private let notAuthorized = NSError(domain: SMAppServiceErrorDomain, code: Int(kSMErrorAuthorizationFailure))
    private let notFound = NSError(domain: SMAppServiceErrorDomain, code: Int(kSMErrorJobNotFound))

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
}
