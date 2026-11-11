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

    /// The category `systemextensionsctl` lists a system extension under, as System Settings names it, or nil when
    /// Peel has no word.
    var categoryName: String? {
        SystemExtensionCategory(category).map { String(localized: $0.word) }
    }

    /// What a row says under the name: the app it came with, or what it plugs into when it carries the app's own
    /// name, so that the parts of one app named after it read apart.
    var rowDetail: String? {
        if goneApp != nil, let name = appName { return String(localized: "\(name), no longer installed") }
        guard let owner else { return pointName }
        guard let pointName, name.localizedCaseInsensitiveCompare(owner) == .orderedSame else { return owner }
        return pointName
    }

    /// `rowDetail`, with the version beside it when another row has this identifier, as during an update.
    func rowDetail(showingVersion: Bool) -> String? {
        let version = showingVersion ? shownVersion.map { String(localized: "Version \($0)") } : nil
        let parts = [rowDetail, version].compactMap(\.self)
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The state to show. macOS keeps a Finder extension off until someone turns it on (`FIFinderSyncController`), so
    /// for one nobody chose, off is what is true, as Home reads it.
    var shownElection: Election {
        election == .asItCame && point == "com.apple.FinderSync" ? .off : election
    }

    var stateExplanation: LocalizedStringResource {
        if election == .waitingForApproval, goneApp != nil {
            return "Its app is gone, so there is nothing to allow. Turning It On and Off, below, says what is left to do."
        }
        return election == .asItCame && shownElection == .off
            ? "macOS keeps a Finder extension off until someone turns it on."
            : election.explanation
    }

    var systemExtensionNote: LocalizedStringResource {
        if #available(macOS 27, *) {
            return systemExtensionNote(isOnMacOS27: true, systemSettingsDeletesIt: systemSettingsDeletesIt)
        }
        return systemExtensionNote(isOnMacOS27: false, systemSettingsDeletesIt: false)
    }

    /// What the page says of a system extension: what its app being gone leaves to do, what macOS is doing with it, or
    /// what moving its app asks of macOS.
    func systemExtensionNote(isOnMacOS27: Bool, systemSettingsDeletesIt: Bool) -> LocalizedStringResource {
        // With its app gone, the advice for an installed app leads nowhere: Orphaned Files' words say what does.
        if goneApp != nil, let reason = leftAlone { return reason.explanation }
        // A version macOS is removing goes on its own, whatever happens to the app.
        if election == .beingRemoved {
            guard let newer = replacedBy else { return election.explanation }
            return "Version \(newer) replaced this one, which macOS is removing. Some removals finish only when the Mac restarts."
        }
        if isForAnAppInsideAnother {
            return "macOS runs this for an app bundled inside another, and no move of that app removes it: Finder asks macOS to remove only the extensions in an app’s own folder. Turn it off first in System Settings > General > Login Items & Extensions."
        }
        if isOnMacOS27 {
            return systemSettingsDeletesIt
                ? "macOS keeps its own copy of this, apart from the app, so Peel leaves that app to Finder. Moving the app to the Trash in Finder asks macOS to remove it. So does System Settings: in General > Login Items & Extensions, choose By Category, click the Info button beside Network Extensions, then click the More button beside it and choose Delete Extension."
                : "macOS keeps its own copy of this, apart from the app, and moving the app to the Trash in Finder asks macOS to remove it, sometimes at the next restart. So Peel leaves that app to Finder."
        }
        return "macOS keeps its own copy of this, apart from the app, and removes it only when the app goes to the Trash in Finder, sometimes at the next restart. So Peel leaves that app to Finder."
    }

    /// Whether a search for `text` finds it, by what its row and page say as well as by its identifiers.
    func matches(_ text: String) -> Bool {
        [name, owner, pointName, categoryName, point, identifier].contains {
            $0.map { SearchText.matches($0, text) } == true
        }
    }
}

private enum SystemExtensionCategory {
    case network, camera, driver, endpointSecurity

    init?(_ identifier: String?) {
        switch identifier {
        case "com.apple.system_extension.network_extension": self = .network
        case "com.apple.system_extension.cmio": self = .camera
        case "com.apple.system_extension.driver_extension": self = .driver
        case "com.apple.system_extension.endpoint_security": self = .endpointSecurity
        default: return nil
        }
    }

    var word: LocalizedStringResource {
        switch self {
        case .network: "Network Extensions"
        case .camera: "Camera Extensions"
        case .driver: "Driver Extensions"
        case .endpointSecurity: "Endpoint Security Extensions"
        }
    }
}

/// An extension point Peel has a word for. Its identifiers come from Apple's App Extension Keys documentation
/// and from extensions' `Info.plist` files. `word` is a switch that forms the whole body of a property on
/// purpose: Xcode's string extraction can miss the words of a switch expression assigned to a local `let`, and
/// those words would then stay English in every language.
private enum ExtensionPoint {
    case finder, fileProviders, sharing, widgets, quickLook, safari, shortcuts, notifications, spotlight, photos,
        messages, network, audio, quickActions, passwords, xcode, photoProjects, smartCards, services

    init?(_ identifier: String) {
        switch identifier {
        case "com.apple.FinderSync": self = .finder
        case "com.apple.fileprovider-nonui", "com.apple.fileprovider-actionsui": self = .fileProviders
        case "com.apple.share-services": self = .sharing
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
        // System Settings' own names for the categories it lists extensions under.
        case .finder: "Finder"
        case .fileProviders: "File Providers"
        case .sharing: "Sharing"
        case .widgets: "Widgets"
        // The feature's name, under a key of its own: the Duplicates page uses "Quick Look" as a command, and
        // some languages write the two differently (Swedish: Överblick for the feature, Överblicka for the command).
        case .quickLook: LocalizedStringResource("Quick Look (extension point)", defaultValue: "Quick Look")
        case .safari: "Safari"
        case .shortcuts: "Shortcuts and Siri"
        case .notifications: "Notifications"
        case .spotlight: "Spotlight"
        case .photos: "Photos Editing"
        case .messages: "Messages"
        case .network: "Network"
        case .audio: "Audio apps"
        case .quickActions: "Actions"
        // Services has a key of its own, since some languages name the category apart from the Services folder the
        // Plug-ins page lists (Ukrainian: Сервіси).
        case .passwords: "Password AutoFill"
        case .xcode: "Xcode Source Editor"
        case .photoProjects: "Photos Projects"
        case .smartCards: "Smart Card Readers"
        case .services: LocalizedStringResource("Services (extension point)", defaultValue: "Services")
        }
    }
}
