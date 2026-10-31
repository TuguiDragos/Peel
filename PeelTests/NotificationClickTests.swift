import Foundation
@testable import Peel
import PeelCore
import Testing
import UserNotifications

@Suite(.serialized) @MainActor struct NotificationClickTests {
    private func click(_ content: UNNotificationContent, on notifications: PeelNotifications) {
        notifications.open(
            tool: content.userInfo[PeelNotifications.toolKey] as? String,
            path: content.userInfo[PeelNotifications.pathKey] as? String
        )
    }

    @Test func oneUpdateOpensItsAppInThisCopyOfPeel() {
        defer {
            Navigator.shared.requestedApp = nil
            Navigator.shared.requestedTool = nil
        }
        let app = URL(filePath: "/Applications/Example.app", directoryHint: .isDirectory)

        click(PeelNotifications.updatesContent(count: 1, firstName: "Example", firstApp: app), on: PeelNotifications())

        #expect(Navigator.shared.requestedApp == app)
        #expect(Navigator.shared.requestedTool == .applications)
    }
}
