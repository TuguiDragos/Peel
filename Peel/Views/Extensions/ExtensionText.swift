import PeelCore
import SwiftUI

extension AppExtension {
    /// The name of what the extension plugs into, in the user's language, or the point's identifier when Peel
    /// has no word for it. It lives in the app because PeelCore has no string catalog. The words follow macOS's
    /// own names in each language (Simplified Chinese calls Finder 访达 and Spotlight 聚焦).
    var pointName: String? {
        guard let point else { return nil }
        return ExtensionPoint(point).map { String(localized: $0.word) } ?? point
    }

    /// What a row says under the name: the app it came with, or what it plugs into when it carries the app's own
    /// name, so that the parts of one app named after it read apart.
    var rowDetail: String? {
        if goneApp != nil, let name = appName { return String(localized: "\(name), no longer installed") }
        guard let owner else { return pointName }
        guard let pointName, name.localizedCaseInsensitiveCompare(owner) == .orderedSame else { return owner }
        return pointName
    }

    /// Whether a search for `text` finds it, by what its row and page say as well as by its identifiers.
    func matches(_ text: String) -> Bool {
        [name, owner, pointName, point, identifier].contains { $0.map { SearchText.matches($0, text) } == true }
    }
}

/// An extension point Peel has a word for. Its identifiers come from Apple's App Extension Keys documentation
/// and from extensions' `Info.plist` files. `word` is a switch that forms the whole body of a property on
/// purpose: Xcode's string extraction can miss the words of a switch expression assigned to a local `let`, and
/// those words would then stay English in every language.
private enum ExtensionPoint {
    case finder, share, widgets, quickLook, safari, shortcuts, notifications, spotlight, photos, messages, network,
        audio, quickActions, passwords, xcode, photoProjects, smartCards, services

    init?(_ identifier: String) {
        switch identifier {
        case "com.apple.FinderSync", "com.apple.fileprovider-nonui", "com.apple.fileprovider-actionsui": self = .finder
        case "com.apple.share-services": self = .share
        case "com.apple.widgetkit-extension": self = .widgets
        case "com.apple.quicklook.preview", "com.apple.quicklook.thumbnail": self = .quickLook
        case "com.apple.Safari.web-extension", "com.apple.Safari.extension", "com.apple.Safari.content-blocker":
            self = .safari
        case "com.apple.intents-service", "com.apple.appintents-extension", "com.apple.intents-ui-service":
            self = .shortcuts
        case "com.apple.usernotifications.content-extension", "com.apple.usernotifications.service": self = .notifications
        case "com.apple.spotlight.import", "com.apple.spotlight.index": self = .spotlight
        case "com.apple.photo-editing": self = .photos
        case "com.apple.message-payload-provider": self = .messages
        case "com.apple.networkextension.packet-tunnel", "com.apple.networkextension.filter-data",
             "com.apple.networkextension.app-proxy":
            self = .network
        case "com.apple.AudioUnit-UI", "com.apple.AudioUnit": self = .audio
        case "com.apple.ui-services": self = .quickActions
        case "com.apple.authentication-services-credential-provider-ui": self = .passwords
        case "com.apple.dt.Xcode.extension.source-editor": self = .xcode
        case "com.apple.photo-project": self = .photoProjects
        case "com.apple.ctk-tokens": self = .smartCards
        case "com.apple.services": self = .services
        default: return nil
        }
    }

    var word: LocalizedStringResource {
        switch self {
        case .finder: "Finder"
        case .share: "Share menu"
        case .widgets: "Widgets"
        // The feature's name, under a key of its own: the Duplicates page uses "Quick Look" as a command, and
        // some languages write the two differently (Swedish: Överblick for the feature, Överblicka for the command).
        case .quickLook: LocalizedStringResource("Quick Look (extension point)", defaultValue: "Quick Look")
        case .safari: "Safari"
        case .shortcuts: "Shortcuts and Siri"
        case .notifications: "Notifications"
        case .spotlight: "Spotlight"
        case .photos: "Photos"
        case .messages: "Messages"
        case .network: "Network"
        case .audio: "Audio apps"
        case .quickActions: "Quick Actions"
        // System Settings' own names for these categories of extensions. Services has a key of its own, since some
        // languages name the category apart from the Services folder the Plug-ins page lists (Ukrainian: Сервіси).
        case .passwords: "Password AutoFill"
        case .xcode: "Xcode Source Editor"
        case .photoProjects: "Photos Projects"
        case .smartCards: "Smart Card Readers"
        case .services: LocalizedStringResource("Services (extension point)", defaultValue: "Services")
        }
    }
}
