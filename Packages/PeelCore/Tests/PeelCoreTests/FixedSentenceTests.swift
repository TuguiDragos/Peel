import Foundation
@testable import PeelCore
@testable import PeelPrivileged
import Testing

/// The app shows each fixed sentence in the reader's language by matching its English text. Every sentence the
/// helper or PeelCore can send must therefore be one of them, and no two may share the same English.
struct FixedSentenceTests {
    @Test func everySentenceIsKnownOnceAndOnlyOnce() {
        let english = FixedSentence.allCases.map(\.english)
        #expect(Set(english).count == english.count)
        #expect(Set(PrivilegedPathPolicy.Rejection.allCases.map(\.explanation)).isSubset(of: english))
        #expect(Set(HelperRefusal.allCases.map(\.rawValue)).isSubset(of: english))
        #expect(english.contains(Subprocess.Failure.timedOut.explanation))
        #expect(english.contains(Subprocess.Failure.canceled.explanation))
    }

    @Test func aSentenceItKnowsIsRecognizedAndOneItDoesNotIsLeftAlone() {
        #expect(FixedSentence(HelperRefusal.notInTrash.rawValue) == .notInTrash)
        #expect(FixedSentence("Bootstrap failed: 5: Input/output error") == nil)
    }
}
