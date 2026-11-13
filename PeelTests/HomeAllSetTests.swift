import Foundation
@testable import Peel
import Testing

struct HomeAllSetTests {
    /// On a standard account the helper isn't missing, since this account can't install it, yet what only an
    /// administrator can move stays: Home doesn't say all is set.
    @Test func aStandardAccountWithoutTheHelperIsSetOnlyForItself() {
        #expect(HomeModel.allSet(helper: .notThisAccount) == .forThisAccount)
        #expect(HomeModel.allSet(helper: .on) == .everything)
    }

    @Test func aStandardAccountHearsEveryWayAnAdministratorSetsUpTheHelper() {
        #expect(HomeModel.allSetDetail(.forThisAccount).key.contains("installs, allows, or repairs Peel’s helper"))
        #expect(HomeModel.allSetDetail(.everything).key == "Peel can see everything it needs to.")
    }
}
