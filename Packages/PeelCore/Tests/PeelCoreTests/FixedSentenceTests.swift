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
        #expect(english.contains(Subprocess.notOnItsOwn))
    }

    @Test func aMoveThatWouldLeaveItsDiskIsRefusedInWordsPeelCanTranslate() {
        let answer = TrashMover.StagedFailure.failed(POSIXError(.EXDEV)).explanation
        #expect(FixedSentence(answer) != nil, "the person reads macOS's own English for a move the helper never makes")
    }

    /// A helper an update left running sends its own version's words, which the app still shows in today's.
    @Test func anOlderHelpersWordsForAVersionMismatchAreStillRecognized() {
        #expect(FixedSentence("Peel’s helper is out of date. Reinstall it in Settings.") == .helperOutOfDate)
        #expect(!HelperRefusal.outOfDate.rawValue.contains("Reinstall"), "Settings offers Repair Helper")
    }

    /// Each says why the helper stops and what to do, and the words an older helper sends still read as the same.
    @Test func theHelpersLinkAndTwoFileRefusalsSayWhyAndWhatToDo() {
        #expect(PrivilegedPathPolicy.Rejection.leadsSomewhere.explanation.hasSuffix("removes only links that lead nowhere."))
        #expect(HelperRefusal.declaredTwice.rawValue.hasSuffix("Move one of them to the Trash first."))
        #expect(FixedSentence("It still leads to something on this Mac.") == .leadsSomewhere)
        #expect(FixedSentence("Two files declare this job.") == .declaredTwice)
    }

    @Test func aSentenceItKnowsIsRecognizedAndOneItDoesNotIsLeftAlone() {
        #expect(FixedSentence(HelperRefusal.notInTrash.rawValue) == .notInTrash)
        #expect(FixedSentence("Bootstrap failed: 5: Input/output error") == nil)
    }
}
