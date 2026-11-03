import Foundation
import PeelPrivileged
import Security
import Testing

struct AdministratorAuthorizationTests {
    @Test func noApprovalHoldsWithoutAnAuthorization() {
        #expect(!AdministratorAuthorization.isGranted(by: Data()))
        #expect(!AdministratorAuthorization.isGranted(by: Data(repeating: 1, count: 31)))
        #expect(!AdministratorAuthorization.isGranted(by: Data((0..<32).map { _ in UInt8.random(in: 0...255) })))
    }

    @Test func anAuthorizationNoAdministratorApprovedHoldsNothing() throws {
        var authorization: AuthorizationRef?
        #expect(AuthorizationCreate(nil, nil, [], &authorization) == errAuthorizationSuccess)
        let made = try #require(authorization)
        defer { AuthorizationFree(made, [.destroyRights]) }
        var external = AuthorizationExternalForm()
        #expect(AuthorizationMakeExternalForm(made, &external) == errAuthorizationSuccess)
        let form = withUnsafeBytes(of: &external) { Data($0) }

        #expect(form.count == 32)
        #expect(!AdministratorAuthorization.isGranted(by: form))
    }

    @Test func macOSKeepsTheRightForAnAdministratorAndThatAuthorizationAlone() throws {
        var definition: CFDictionary?
        #expect(AuthorizationRightGet(AdministratorAuthorization.right, &definition) == errAuthorizationSuccess)
        let rule = try #require(definition as? [String: Any])

        #expect(rule["class"] as? String == "user")
        #expect(rule["group"] as? String == "admin")
        #expect(rule["authenticate-user"] as? Bool == true)
        #expect(rule["shared"] as? Bool == false)
        #expect((rule["timeout"] as? Int ?? 0) > 0)
    }
}
