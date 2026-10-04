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

    private struct Entry: Identifiable, Equatable {
        let id: Int
    }

    @Test func findsTheItemsWhoseKeyHoldsTheQueryInTheirOrder() async {
        let items = (0..<5).map(Entry.init)
        let keys = [0: "Duplicates\nReport 1.pdf", 1: "Developer\nnotes.txt", 2: "Duplicates\nRÉPORT 2.pdf", 4: "report"]

        #expect(await SearchText.matching("report", among: items, keys: keys) == [items[0], items[2], items[4]])
        #expect(await SearchText.matching("nothing", among: items, keys: keys) == [])
    }

    @Test func givesUpWhenTheSearchIsCanceled() async {
        let items = (0..<5).map(Entry.init)
        let task = Task { () -> [Entry]? in
            withUnsafeCurrentTask { $0?.cancel() }
            return await SearchText.matching("report", among: items, keys: [0: "report"])
        }
        #expect(await task.value == nil)
    }

    @Test func findsNothingThatIsNotThere() {
        #expect(!SearchText.matches("Safari", "chrome", locale: Self.turkish))
        #expect(!SearchText.matches("Safari", "", locale: Self.turkish))
    }
}
