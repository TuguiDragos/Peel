import Foundation

extension String {
    /// Builds a localized string with automatic grammar agreement applied.
    ///
    /// `String(localized:)` leaves inflection markup such as `^[2 app](inflect: true)` in the text as written.
    /// Only `AttributedString` resolves it, so the text is built there and flattened for the places that need a
    /// plain `String`: a notification's title and body, and anything handed to AppKit rather than to SwiftUI.
    init(inflecting key: String.LocalizationValue) {
        self = String(AttributedString(localized: key).characters)
    }
}

extension LocalizedStringResource {
    /// The English text of this resource, whatever language the app runs in. Used for text stored where the
    /// English-only `peel` tool reads it too, such as the source of a History entry.
    var inEnglish: String {
        var english = self
        english.locale = Locale(identifier: "en")
        return String(localized: english)
    }
}
