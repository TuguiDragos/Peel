import Foundation
@testable import Peel
import PeelCore
import Testing

@MainActor
struct PutBackTitleTests {
    @Test func countsWhatStayedAndSaysWhenNothingWentBack() {
        #expect(RestoreFailure.title(stayed: 1, of: 1) == "1 item couldn’t be put back.")
        #expect(RestoreFailure.title(stayed: 2, of: 5) == "2 items couldn’t be put back.")
        #expect(RestoreFailure.title(stayed: 3, of: 3) == "None of these could be put back.")
    }
}
