import Foundation
@testable import Peel
import PeelCore
import Testing

@MainActor
struct HelperReasonTests {
    @Test func saysWhyTheHelperCannotActWithoutPromisingItWillSoon() {
        let reason = { (standing: PrivilegedHelper.Standing, anotherCopy: Bool) in
            String(localized: standing.whyItCannotAct(registeredByAnotherCopy: anotherCopy, status: .notRegistered))
        }

        #expect(reason(.notInstalled, false) == String(localized: "Install Peel’s helper, which does this as an administrator in the system folders it serves."))
        #expect(reason(.notInstalled, true) == String(localized: "Peel’s helper was installed by another copy of Peel, and this copy can’t use it. Open the copy of Peel that installed it."))
        #expect(reason(.waitingForApproval, false) == String(localized: "Peel’s helper is waiting to be allowed in System Settings > General > Login Items & Extensions."))
        #expect(reason(.notAnswering, false) == String(localized: "Peel’s helper isn’t answering. Repair it in Settings."))
    }

    @Test func tellsAnAccountThatIsNotAnAdministratorsWhereTheHelperStandsAndTheStep() {
        let told = { (status: PrivilegedHelper.Status) in
            String(localized: PrivilegedHelper.Standing.notThisAccount.whyItCannotAct(
                registeredByAnotherCopy: false, status: status
            ))
        }
        let said = [told(.notRegistered), told(.requiresApproval), told(.enabled)]

        #expect(told(.unavailable) == said[0])
        #expect(said[0].contains("isn’t installed") && said[0].contains("install the helper"))
        #expect(said[1].contains("not yet allowed") && said[1].contains("allow the helper"))
        #expect(said[2].contains("isn’t answering") && said[2].contains("repair the helper"))
        #expect(said.allSatisfy { $0.contains("Log in as an administrator") && $0.contains("this account can use it") })
    }

    @Test func offersNoInstallToACopyThatDidNotRegisterIt() {
        #expect(PrivilegedHelper.Standing.notInstalled.offersInstall(registeredByAnotherCopy: false))
        #expect(!PrivilegedHelper.Standing.notInstalled.offersInstall(registeredByAnotherCopy: true))
        #expect(!PrivilegedHelper.Standing.ready.offersInstall(registeredByAnotherCopy: false))
    }

    @Test func offersUninstallOnlyToAnAdministrator() {
        #expect(PrivilegedHelper.Standing.ready.offersUninstall(isAdministrator: true))
        #expect(!PrivilegedHelper.Standing.ready.offersUninstall(isAdministrator: false))
        #expect(PrivilegedHelper.Standing.waitingForApproval.offersUninstall(isAdministrator: true))
        #expect(PrivilegedHelper.Standing.notAnswering.offersUninstall(isAdministrator: true))
        #expect(!PrivilegedHelper.Standing.notInstalled.offersUninstall(isAdministrator: true))
        #expect(!PrivilegedHelper.Standing.notThisAccount.offersUninstall(isAdministrator: false))
    }
}
