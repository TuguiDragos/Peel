import Foundation
@testable import Peel
import Testing

@MainActor
struct OrphanSummaryTests {
    @Test func saysWhatOnlyAnAdministratorCanMoveApartFromTheGroups() {
        #expect(OrphanLibrary.summary(groups: nil, forAnAdministrator: 0) == nil)
        #expect(OrphanLibrary.summary(groups: nil, forAnAdministrator: 2).map { String($0.characters) }
            == "2 items only an administrator can move.")
    }
}
