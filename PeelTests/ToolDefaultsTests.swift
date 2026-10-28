import Foundation
@testable import Peel
import Testing

struct ToolDefaultsTests {
    @Test func showsICloudDriveByDefaultOnlyWhereItIsSetUp() {
        #expect(Tool.cloud.isShownByDefault(homebrewIsInstalled: true, hasICloudDrive: true))
        #expect(!Tool.cloud.isShownByDefault(homebrewIsInstalled: true, hasICloudDrive: false))
        #expect(!Tool.homebrew.isShownByDefault(homebrewIsInstalled: false, hasICloudDrive: true))
        #expect(Tool.duplicates.isShownByDefault(homebrewIsInstalled: false, hasICloudDrive: false))
    }
}
