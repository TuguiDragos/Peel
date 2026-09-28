@testable import PeelCore
import Testing
import UserNotifications

struct NotificationPresentationTests {
    /// A notice stays in Notification Center whatever is in front, and shows as a banner only while Peel is not,
    /// since its window already says what the banner would.
    @Test func keepsEveryNoticeAndShowsABannerOnlyBehindAnotherApp() {
        #expect(NotificationPresentation.options(whilePeelIsActive: true) == [.list])
        #expect(NotificationPresentation.options(whilePeelIsActive: false) == [.banner, .list])
    }
}
