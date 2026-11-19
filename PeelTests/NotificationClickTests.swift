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

    @Test func severalUpdatesOpenTheListWithNoAppChosen() throws {
        defer {
            Navigator.shared.requestedApp = nil
            Navigator.shared.requestedTool = nil
        }
        let madeUp = try MadeUpDefaults()
        defer { madeUp.forget() }
        let folder = FileManager.default.temporaryDirectory.appending(
            path: "NotificationClickTests-\(UUID().uuidString)", directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: folder) }
        let library = AppLibrary(defaults: madeUp.defaults, appMemory: AppMemory(url: folder.appending(path: "apps.json")))
        let app = InstalledApp(
            url: URL(filePath: "/Applications/Example.app", directoryHint: .isDirectory),
            bundleIdentifier: "org.example.app", name: "Example"
        )
        library.selection = [app.id]
        let notifications = PeelNotifications()
        notifications.appList = library

        click(PeelNotifications.updatesContent(count: 3, firstName: "Example", firstApp: app.url), on: notifications)

        #expect(Navigator.shared.requestedApp == nil)
        #expect(Navigator.shared.requestedTool == .applications)
        #expect(library.selection.isEmpty)
    }
}
