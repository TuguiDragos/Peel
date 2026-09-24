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
}

/// An extension point Peel has a word for. Its identifiers come from Apple's App Extension Keys documentation
/// and from extensions' `Info.plist` files. `word` is a switch that forms the whole body of a property on
/// purpose: Xcode's string extraction can miss the words of a switch expression assigned to a local `let`, and
/// those words would then stay English in every language.
private enum ExtensionPoint {
    case finder, share, widgets, quickLook, safari, shortcuts, notifications, spotlight, photos, messages, network, audio, quickActions

    init?(_ identifier: String) {
        switch identifier {
        case "com.apple.FinderSync", "com.apple.fileprovider-nonui", "com.apple.fileprovider-actionsui": self = .finder
        case "com.apple.share-services": self = .share
        case "com.apple.widgetkit-extension": self = .widgets
        case "com.apple.quicklook.preview", "com.apple.quicklook.thumbnail": self = .quickLook
        case "com.apple.Safari.web-extension", "com.apple.Safari.extension": self = .safari
        case "com.apple.intents-service", "com.apple.appintents-extension": self = .shortcuts
        case "com.apple.usernotifications.content-extension", "com.apple.usernotifications.service": self = .notifications
        case "com.apple.spotlight.import", "com.apple.spotlight.index": self = .spotlight
        case "com.apple.photo-editing": self = .photos
        case "com.apple.message-payload-provider": self = .messages
        case "com.apple.networkextension.packet-tunnel", "com.apple.networkextension.filter-data": self = .network
        case "com.apple.AudioUnit-UI", "com.apple.AudioUnit": self = .audio
        case "com.apple.ui-services": self = .quickActions
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
        }
    }
}

#if DEBUG
extension AppExtension {
    /// Checks `pointName`: a known point gets a word, an unknown point keeps its identifier, and an extension
    /// with no point gets nil. The app has no test target, so Debug builds run this when the main window opens.
    static func checkWords() {
        func made(_ point: String?) -> AppExtension {
            AppExtension(
                identifier: "x", name: "x", kind: .appExtension, point: point, owner: nil,
                url: URL(filePath: "/x"), election: .asItCame, teamIdentifier: nil, reportedState: nil
            )
        }
        assert(made("com.apple.FinderSync").pointName?.isEmpty == false, "Finder has no word")
        assert(made("com.apple.FinderSync").pointName != "com.apple.FinderSync", "Finder kept its identifier")
        assert(made("com.example.unknown").pointName == "com.example.unknown", "an unknown point lost its identifier")
        assert(made(nil).pointName == nil, "no point was given a name")
    }
}
#endif
