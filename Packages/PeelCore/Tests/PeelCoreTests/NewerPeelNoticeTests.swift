@testable import PeelCore
import Testing

struct NewerPeelNoticeTests {
    @Test func tellsOnceForEachNewerVersion() {
        #expect(NewerPeelNotice.check(newer: nil, told: nil) == .init(tell: false, told: nil))
        #expect(NewerPeelNotice.check(newer: "1.0.2", told: nil) == .init(tell: true, told: "1.0.2"))
        #expect(NewerPeelNotice.check(newer: "1.0.2", told: "1.0.2") == .init(tell: false, told: "1.0.2"))
        #expect(NewerPeelNotice.check(newer: "1.0.3", told: "1.0.2") == .init(tell: true, told: "1.0.3"))
    }

    @Test func keepsWhatItToldOnceThisCopyIsUpToDate() {
        #expect(NewerPeelNotice.check(newer: nil, told: "1.0.3") == .init(tell: false, told: "1.0.3"))
    }
}
