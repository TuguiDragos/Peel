import Foundation
@testable import Peel
import PeelCore
import Testing

@MainActor
struct HelperReasonTests {
    @Test func saysWhyTheHelperCannotActWithoutPromisingItWillSoon() {
        let reason = { (standing: PrivilegedHelper.Standing, anotherCopy: Bool) in
            String(localized: standing.whyItCannotAct(registeredByAnotherCopy: anotherCopy))
        }

        #expect(reason(.notThisAccount, false) == String(localized: "Only an administrator can use Peel’s helper, so Peel can’t do this from this account."))
        #expect(reason(.notInstalled, false) == String(localized: "Install Peel’s helper, which does this as an administrator in the system folders it serves."))
        #expect(reason(.notInstalled, true) == String(localized: "Peel’s helper was installed by another copy of Peel, and this copy can’t use it. Open the copy of Peel that installed it."))
        #expect(reason(.waitingForApproval, false) == String(localized: "Peel’s helper is waiting to be allowed in System Settings, under Login Items & Extensions."))
        #expect(reason(.notAnswering, false) == String(localized: "Peel’s helper isn’t answering. Repair it in Settings."))
    }

    @Test func offersNoInstallToACopyThatDidNotRegisterIt() {
        #expect(PrivilegedHelper.Standing.notInstalled.offersInstall(registeredByAnotherCopy: false))
        #expect(!PrivilegedHelper.Standing.notInstalled.offersInstall(registeredByAnotherCopy: true))
        #expect(!PrivilegedHelper.Standing.ready.offersInstall(registeredByAnotherCopy: false))
    }
}
