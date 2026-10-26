@testable import Peel
import Testing
import UserNotifications

struct NotificationNeedTests {
    @Test func onlyARefusalCountsAsTurnedOff() {
        #expect(PeelNotifications.areTurnedOff(.denied))
        #expect(!PeelNotifications.areTurnedOff(.authorized))
        #expect(!PeelNotifications.areTurnedOff(.provisional))
        #expect(!PeelNotifications.areTurnedOff(.notDetermined))
    }
}
