@testable import Peel
import Testing

@MainActor
struct WaitingPermissionsTests {
    @Test func namesTheHelperAsSystemSettingsDoes() {
        typealias Waiting = HomeModel.Permission.Waiting
        let named = HomeModel.Permission.inSystemSettings

        #expect(named([.helper]) == Waiting(allowsPeel: true, others: []))
        #expect(named([.fullDiskAccess, .helper]) == Waiting(allowsPeel: true, others: [.fullDiskAccess]))
        #expect(named([.fullDiskAccess]) == Waiting(allowsPeel: false, others: [.fullDiskAccess]))
    }
}
