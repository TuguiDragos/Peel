import Foundation

public enum ScreenshotName {
    public enum Problem: Sendable, Equatable {
        case separator
        case hidden
        case tooLong
    }

    static let longestName = 200

    public static func problem(with name: String) -> Problem? {
        if name.contains("/") || name.contains(":") { return .separator }
        if name.hasPrefix(".") { return .hidden }
        if name.utf8.count > longestName { return .tooLong }
        return nil
    }

    /// What macOS names a screenshot. `screencaptureui` names its files in the language of the session, which a person
    /// can set apart from this app's.
    public static var macOSDefault: String? {
        let languages = CFPreferencesCopyValue(
            "AppleLanguages" as CFString, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost
        ) as? [String]
        return macOSDefault(preferring: languages ?? Locale.preferredLanguages)
    }

    static func macOSDefault(preferring languages: [String]) -> String? {
        guard let bundle = Bundle(path: "/System/Library/CoreServices/screencaptureui.app"),
              let language = Bundle.preferredLocalizations(from: bundle.localizations, forPreferences: languages).first
        else { return nil }
        return bundle.localizedString(
            forKey: "Screenshot", value: nil, table: "Localizable", localizations: [Locale.Language(identifier: language)]
        )
    }
}
