import Foundation
@testable import PeelCore
import Testing

struct DeviceManagementTests {
    @Test func readsWhetherAnOrganizationEnrolledTheMac() {
        #expect(DeviceManagement.enrollment(in: "Enrolled via DEP: No\nMDM enrollment: No\n") == .notEnrolled)
        #expect(DeviceManagement.enrollment(in: "Enrolled via DEP: Yes\nMDM enrollment: Yes (User Approved)\n") == .enrolled)
        #expect(DeviceManagement.enrollment(in: "MDM enrollment: Yes\n") == .enrolled)
        #expect(DeviceManagement.enrollment(in: "profiles: an option it does not know\n") == nil)
        #expect(DeviceManagement.enrollment(in: nil) == nil)
    }

    /// Any account may ask `profiles`, so this asks this Mac itself, and waits for its whole answer.
    @Test func readsThisMac() async {
        #expect(await DeviceManagement.read(within: nil) != nil)
    }
}
