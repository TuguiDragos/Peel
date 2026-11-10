import Foundation
@testable import Peel
import PeelCore
import Testing

struct AppSourceTitleTests {
    /// An app built here or copied from a disk was never downloaded, so the filter doesn't say it was.
    @Test func theFilterSaysOtherForAnAppFromNoneOfTheOthers() {
        #expect(String(localized: AppSource.direct.title) == String(localized: "Other"))
    }
}
