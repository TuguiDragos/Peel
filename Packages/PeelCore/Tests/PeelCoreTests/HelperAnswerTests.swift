import Foundation
@testable import PeelCore
import Testing

struct HelperAnswerTests {
    @Test func theTimerThatEndsAWaitForTheHelperNeverWaitsBehindWorkOfLowerQuality() {
        #expect(PrivilegedHelper.timers.label == DispatchQueue.global(qos: .userInitiated).label)
    }
}
