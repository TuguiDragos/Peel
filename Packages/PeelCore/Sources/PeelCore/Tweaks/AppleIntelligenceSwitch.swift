public import Foundation

/// An Apple Intelligence feature and the place Apple's Mac User Guide for macOS 27 names for turning it off ("Turn off
/// and restrict access to Apple Intelligence features on Mac"). Peel only opens the place: the switch stays macOS's.
public enum AppleIntelligenceSwitch: String, CaseIterable, Sendable {
    case siri
    case notificationSummaries
    case messagesSummaries
    case emailSummaries
    case smartReplies
    case voicemailSuggestions
    case writingPrompts
    case screenTime

    public enum Place: Sendable, Hashable {
        case settings(address: URL)
        case app(bundleIdentifier: String)
    }

    public var place: Place {
        switch self {
        case .siri: .settings(address: Self.pane("com.apple.Siri-Settings.extension"))
        case .notificationSummaries: .settings(address: Self.pane("com.apple.Notifications-Settings.extension"))
        case .screenTime:
            .settings(address: Self.pane("com.apple.Screen-Time-Settings.extension?path=content-and-privacy"))
        case .messagesSummaries: .app(bundleIdentifier: "com.apple.MobileSMS")
        case .emailSummaries, .smartReplies: .app(bundleIdentifier: "com.apple.mail")
        case .voicemailSuggestions: .app(bundleIdentifier: "com.apple.mobilephone")
        case .writingPrompts: .app(bundleIdentifier: "com.apple.journal")
        }
    }

    private static func pane(_ address: String) -> URL {
        URL(string: "x-apple.systempreferences:" + address)!
    }
}
