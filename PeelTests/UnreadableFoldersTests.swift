@testable import Peel
import Testing

struct UnreadableFoldersTests {
    @Test func namesTheFirstFourFoldersAndCountsTheRest() {
        let paths = (1...60).map { "/Volumes/Old/f\($0)x" }

        let sentence = RemovalFailureAlert.listedFolders(paths)

        #expect(sentence.contains("f4x") && !sentence.contains("f5x") && !sentence.contains("f60x"))
        #expect(sentence.contains("56"))
        #expect(RemovalFailureAlert.listedFolders(["/a", "/b"]).contains("/b"))
    }

    @Test func anAlertsFirstItemsAndHowManyMore() {
        let (shown, more) = RemovalFailureAlert.first(Array(1...60))

        #expect(shown == [1, 2, 3, 4] && more == 56)
        #expect(RemovalFailureAlert.first([1, 2]) == ([1, 2], 0))
    }
}
