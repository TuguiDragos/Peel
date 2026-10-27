import Foundation
@testable import Peel
import Testing

struct ToolDefaultsTests {
    /// iCloud Drive's page starts on only where iCloud Drive is set up, as Homebrew's does only with Homebrew.
    @Test func showsICloudDriveByDefaultOnlyWhereItIsSetUp() {
        #expect(Tool.cloud.isShownByDefault(homebrewIsInstalled: true, hasICloudDrive: true))
        #expect(!Tool.cloud.isShownByDefault(homebrewIsInstalled: true, hasICloudDrive: false))
        #expect(!Tool.homebrew.isShownByDefault(homebrewIsInstalled: false, hasICloudDrive: true))
        #expect(Tool.duplicates.isShownByDefault(homebrewIsInstalled: false, hasICloudDrive: false))
    }
}
