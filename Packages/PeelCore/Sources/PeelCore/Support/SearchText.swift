public import Foundation

/// How every search field matches text. Case, accents and width are ignored, so full-width letters typed with a
/// Japanese, Chinese or Korean input method still match. The user's locale is tried first, then no locale: in
/// Turkish, `I` folds to `ı`, so `iina` would miss IINA, and the second pass finds it.
public enum SearchText {
    public static func matches(_ text: String, _ query: String, locale: Locale = .current) -> Bool {
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]
        return text.range(of: query, options: options, locale: locale) != nil
            || text.range(of: query, options: options) != nil
    }
}
