import AppKit
import Foundation
import PeelCore
import SwiftUI
import UserNotifications

final class PeelNotifications: NSObject, UNUserNotificationCenterDelegate {
    nonisolated static let pathKey = "path"
    nonisolated static let toolKey = "tool"

    /// The list of apps, whose chosen row a click that opens the whole list clears.
    var appList: AppLibrary?

    func activate() {
        UNUserNotificationCenter.current().delegate = self
    }

    /// Asks macOS to let Peel send notifications. macOS asks the person only the first time, and keeps the answer.
    static func requestAuthorization() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert])
    }

    /// Whether the person refused Peel's notifications. An answer not given yet is no refusal: Peel asks when a
    /// switch that needs them is turned on.
    nonisolated static func areTurnedOff(_ status: UNAuthorizationStatus) -> Bool {
        status == .denied
    }

    static func mayShow() async -> Bool {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        return status == .authorized || status == .provisional
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
        let content = Self.updatesContent(count: count, firstName: firstName, firstApp: firstApp)
        let request = UNNotificationRequest(identifier: "updates", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    static func updatesContent(count: Int, firstName: String, firstApp: URL) -> UNNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = count == 1
            ? String(localized: "\(firstName) has an update")
            : String(inflecting: "^[\(count) app](inflect: true) have new updates")
        content.body = String(localized: "Peel doesn’t install updates on its own. Click to see what’s waiting, under Applications.")
        // One update opens that app's page, where it is updated. Several open the list, which leads with them, rather
        // than one app's page with its files selected for removal.
        content.userInfo = count == 1
            ? [Self.pathKey: firstApp.path(percentEncoded: false)] : [Self.toolKey: Tool.applications.rawValue]
        return content
    }

    /// Answers a click in this copy of Peel, as a Shortcut does: a `peel://` link goes to whichever copy Launch
    /// Services prefers.
    func open(tool: String?, path: String?) {
        if let path {
            Navigator.shared.requestedApp = URL(filePath: path, directoryHint: .isDirectory)
            Navigator.shared.show(.applications)
        } else if let tool = tool.flatMap(Tool.init(rawValue:)) {
            if tool == .applications { appList?.selection = [] }
            Navigator.shared.show(tool)
        }
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
        await MainActor.run { NotificationPresentation.options(whilePeelIsActive: NSApp.isActive) }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        let (tool, path) = (userInfo[Self.toolKey] as? String, userInfo[Self.pathKey] as? String)
        await MainActor.run { open(tool: tool, path: path) }
    }
}

extension EnvironmentValues {
    /// The notification sender set up at launch, so a view can tell the user about work that finished while
    /// Peel was in the background.
    @Entry var notifications: PeelNotifications?
}
