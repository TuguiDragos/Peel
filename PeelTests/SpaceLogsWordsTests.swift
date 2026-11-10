import Foundation
@testable import Peel
import PeelCore
import Testing

struct SpaceLogsWordsTests {
    /// The area offers the apps' logs too, and only the crash reports' folder stays.
    @Test func theLogsAreaSaysTheReportsFolderStays() throws {
        let detail = try #require(SpaceItem.words(for: "logs")).detail.key

        #expect(detail.hasSuffix("The crash reports are offered one by one, and the folder they sit in always stays."), "\(detail)")
    }
}
