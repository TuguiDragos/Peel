import Foundation

/// A web app saved from a browser as an app of its own, which the browser keeps: its shortcut is the bundle, and
/// what makes it an app stays with the browser that saved it.
public enum WebApp: Sendable, Hashable {
    /// One Safari made (`SafariWebApp`), whose data Safari keeps in a container named by its identifier.
    case safari
    /// One a Chromium browser made, such as Google Chrome. The browser keeps the app and its data in its profile, so
    /// moving the shortcut leaves the app in the browser, which can make the shortcut again.
    case browser(identifier: String)

    /// The kind of web app `info`, an app's Info.plist, says it is, or nil for any other app.
    static func of(identifier: String, info: [String: Any]) -> WebApp? {
        if SafariWebApp.isOne(identifier: identifier, info: info) { return .safari }
        // Chromium writes the browser's identifier and the app's own into the shortcut it makes, and names the
        // shortcut by the browser's identifier followed by `.app.` (`app_mode_common.mm`,
        // `GetBundleIdentifierForShim` in `web_app_shortcut_mac.mm`).
        guard
            let browser = info["CrBundleIdentifier"] as? String, !browser.isEmpty,
            let app = info["CrAppModeShortcutID"] as? String, !app.isEmpty,
            identifier.hasPrefix(browser + ".app.")
        else { return nil }
        return .browser(identifier: browser)
    }
}
