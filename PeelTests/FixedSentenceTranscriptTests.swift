import Foundation
@testable import Peel
import PeelCore
import Testing

@MainActor
struct FixedSentenceTranscriptTests {
    @Test func aTranscriptEndsWithPeelsSentenceInTheReadersLanguage() throws {
        let romanian = try #require(Bundle.main.url(forResource: "ro", withExtension: "lproj").flatMap(Bundle.init(url:)))
        let stopped = FixedSentence.toolStopped.words.resolved(in: romanian)
        #expect(stopped != FixedSentence.toolStopped.english)

        let shown = FixedSentence.translated("==> Upgrading a\n\(FixedSentence.toolStopped.english)\n", in: romanian)

        #expect(shown == "==> Upgrading a\n\(stopped)")
        #expect(FixedSentence.translated("==> Upgrading a\nDone.\n", in: romanian) == "==> Upgrading a\nDone.\n")
    }
}
