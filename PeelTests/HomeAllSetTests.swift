import Foundation
@testable import Peel
import PeelCore
import Testing

struct HomeAllSetTests {
    /// On a standard account the helper isn't missing, since this account can't install it, yet what only an
    /// administrator can move stays: Home doesn't say all is set.
    @Test func aStandardAccountWithoutTheHelperIsSetOnlyForItself() {
        #expect(HomeModel.allSet(helper: .notThisAccount) == .forThisAccount)
        #expect(HomeModel.allSet(helper: .on) == .everything)
    }

    @Test func aStandardAccountHearsEveryWayAnAdministratorSetsUpTheHelper() {
        let step = PrivilegedHelper.Standing.notThisAccount.whyItCannotAct(
            registeredByAnotherCopy: false, status: .notRegistered
        )
        let note = HomeModel.allSetNote(.forThisAccount, helper: step).map { String(localized: $0) }
        #expect(note == String(localized: step))
        #expect(HomeModel.allSetNote(.everything, helper: step) == nil)
    }
}
