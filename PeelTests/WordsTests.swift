import Foundation
@testable import Peel
@testable import PeelCore
import Testing

/// Each reads the English keys, not the text they resolve to, so a pseudolanguage can't trip it. `StringCatalogTests`
/// checks the translations.
struct WordsTests {
    @Test func everyTweakHasATitleAndExplainsItself() {
        for id in TweakCatalog.all.map(\.id) {
            let found = Tweak.words(for: id)
            #expect(found != nil, "no words for \(id)")
            #expect(found?.title.key.isEmpty == false, "\(id) has no title")
            #expect(found?.detail.key.hasSuffix(".") == true, "\(id) doesn't explain itself")
        }
    }

    @Test func everyAreaOfTheDiskHasATitleAndExplainsItself() {
        for id in SpaceInventory.definitionIdentifiers {
            let found = SpaceItem.words(for: id)
            #expect(found != nil, "no words for \(id)")
            #expect(found?.title.key.isEmpty == false, "\(id) has no title")
            #expect(found?.detail.key.hasSuffix(".") == true, "\(id) doesn't explain itself")
            #expect(found?.hint?.key.isEmpty != true, "\(id) has an empty hint")
        }
        for id in SpaceInventory.managedAreaIdentifiers {
            #expect(SpaceItem.words(for: id)?.hintWithoutItsApp != nil, "\(id) has no hint for when its app is gone")
        }
    }

    @Test func anExtensionPointIsNamedInWordsOrByItsIdentifier() {
        func made(_ point: String?) -> AppExtension {
            AppExtension(
                identifier: "org.example.part", name: "Part", kind: .appExtension, point: point, owner: nil,
                url: URL(filePath: "/org.example"), election: .asItCame, teamIdentifier: nil, reportedState: nil
            )
        }

        #expect(made("com.apple.FinderSync").pointName?.isEmpty == false, "Finder has no word")
        #expect(made("com.apple.FinderSync").pointName != "com.apple.FinderSync", "Finder kept its identifier")
        #expect(made("com.example.unknown").pointName == "com.example.unknown", "an unknown point lost its identifier")
        #expect(made(nil).pointName == nil, "no point was given a name")
    }

    @Test func everyFixedSentenceReadsAsWhatIsSent() {
        for sentence in FixedSentence.allCases {
            #expect(sentence.words.key == sentence.english, "the words for \(sentence) no longer read as what is sent")
        }
    }
}
