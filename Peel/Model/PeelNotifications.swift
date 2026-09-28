import AppKit
import Foundation
import PeelCore
import PeelLink
import SwiftUI
import UserNotifications

final class PeelNotifications: NSObject, UNUserNotificationCenterDelegate {
    private nonisolated static let pathKey = "path"
    private nonisolated static let toolKey = "tool"

    func activate() {
        UNUserNotificationCenter.current().delegate = self
    }

    func requestAuthorization() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert])
    }

    func notify(applicationTrashed url: URL) {
        let content = UNMutableNotificationContent()
        let name = AppInspector.displayName(of: url)
        content.title = String(localized: "\(name) is in the Trash")
        content.body = String(localized: "Click to see what it left behind, under Applications.")
        content.userInfo = [Self.pathKey: url.path(percentEncoded: false)]
        let request = UNNotificationRequest(identifier: url.path(percentEncoded: false), content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    /// Tells the user that a Homebrew upgrade finished. An upgrade can take long enough that the user has
    /// moved on to something else.
    func notify(appUpgraded name: String, to version: String?, app url: URL) {
        let content = UNMutableNotificationContent()
        content.title = version.map { String(localized: "\(name) is now \($0)") } ?? String(localized: "\(name) is up to date")
        content.body = String(localized: "Homebrew finished the upgrade.")
        content.userInfo = [Self.pathKey: url.path(percentEncoded: false)]
        let request = UNNotificationRequest(identifier: "upgraded-\(url.path(percentEncoded: false))", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    func notify(appUpgradeFailed name: String, app url: URL) {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "\(name) wasn’t upgraded")
        content.body = String(localized: "Homebrew ran into a problem. What it said is on the app’s page in Peel, if that page is still open.")
        content.userInfo = [Self.pathKey: url.path(percentEncoded: false)]
        let request = UNNotificationRequest(identifier: "upgraded-\(url.path(percentEncoded: false))", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    /// One notification for the whole round of checks, never one per app.
    func notify(updatesAvailable count: Int, firstName: String, firstApp: URL) {
        guard count > 0 else { return }
        let content = UNMutableNotificationContent()
        content.title = count == 1
            ? String(localized: "\(firstName) has an update")
            : String(inflecting: "^[\(count) app](inflect: true) have new updates")
        content.body = String(localized: "Peel doesn’t install updates on its own. Click to see what’s waiting, under Applications.")
        content.userInfo = [Self.pathKey: firstApp.path(percentEncoded: false)]
        let request = UNNotificationRequest(identifier: "updates", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    func notify(diskNearlyFull storage: DeviceInfo.Storage) {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Your disk is almost full")
        content.body = String(localized: "\(storage.free.byteCount) available of \(storage.total.byteCount). Click to see what’s using it, under Space.")
        content.userInfo = [Self.toolKey: Tool.space.rawValue]
        let request = UNNotificationRequest(identifier: "disk-nearly-full", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // No banner while Peel is the active app: the user is already looking at its window.
        await MainActor.run { NSApp.isActive ? [] : [.banner] }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        if let tool = response.notification.request.content.userInfo[Self.toolKey] as? String {
            await MainActor.run {
                if let tool = Tool(rawValue: tool) {
                    Navigator.shared.show(tool)
                }
            }
            return
        }
        guard
            let path = response.notification.request.content.userInfo[Self.pathKey] as? String,
            let url = OpenRequest.link(toApplicationAt: path)
        else { return }
        await MainActor.run {
            _ = NSWorkspace.shared.open(url)
        }
    }
}

extension EnvironmentValues {
    /// The notification sender set up at launch, so a view can tell the user about work that finished while
    /// Peel was in the background.
    @Entry var notifications: PeelNotifications?
}
