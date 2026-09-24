import Foundation
import PeelCore
import Testing

/// When Peel runs in Turkish (`tr_TR`), `localizedStandardContains` matches none of the first eight pairs below.
@Suite struct SearchTextTests {
    static let turkish = Locale(identifier: "tr_TR")

    @Test(arguments: [
        ("Illustrator", "illustrator"), ("IINA", "iina"), ("Insomnia", "ins"), ("Firefox", "FIREFOX"), ("GIMP", "gimp"),
        ("Itsycal", "i"), ("com.apple.Finder", "FINDER"), ("İstanbul Radyo", "istanbul"), ("Kırmızı Notlar", "KIRMIZI"),
        ("Ärger", "arger"), ("Straße", "strasse"),
    ])
    func findsANameUnderTurkishRules(name: String, typed: String) {
        #expect(SearchText.matches(name, typed, locale: Self.turkish))
    }

    /// The reason for the second pass: Turkish rules alone fold `I` to `ı`.
    @Test func turkishRulesAloneMissAnEnglishName() {
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]
        #expect("IINA".range(of: "iina", options: options, locale: Self.turkish) == nil)
    }

    @Test func findsFullWidthLettersTypedThroughAnEastAsianInput() {
        #expect(SearchText.matches("Safari", "ｓａｆａｒｉ", locale: Locale(identifier: "ja_JP")))
    }

    @Test func findsNothingThatIsNotThere() {
        #expect(!SearchText.matches("Safari", "chrome", locale: Self.turkish))
        #expect(!SearchText.matches("Safari", "", locale: Self.turkish))
    }
}
