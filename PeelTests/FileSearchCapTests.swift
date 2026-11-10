import Foundation
@testable import Peel
import PeelCore
import Testing

struct FileSearchCapTests {
    /// The line shows without the filters' note, so it says itself which files come last.
    @Test func theCapLineSaysWhatComesLast() {
        #expect(FileSearchList.capWords == String(inflecting: "Peel lists at most ^[\(FileSearch.maximumResults) file](inflect: true): the largest first, with what apps keep in a Library folder last. Narrow the search to see the rest."))
    }
}
