import Foundation
@testable import PeelCore
import Testing

@MainActor
struct RemovalQuestionTests {
    private let first = RemovalRequest(urls: [URL(filePath: "/Users/me/Library/Caches/a")], sizes: [:])

    /// The question asks about the selection as it was when it appeared, and the move takes exactly that.
    @Test func startsTheRemovalItAskedAbout() {
        let question = RemovalQuestion()
        question.ask(first)

        #expect(question.isAsking)
        #expect(question.start() == first)
    }

    /// The question stands for what it showed: a selection that changes under it closes it, and one that stays
    /// the same leaves it up.
    @Test func closesWhenTheSelectionChangesUnderIt() {
        let question = RemovalQuestion()
        question.ask(first)

        question.selectionChanged(to: first.urls)
        #expect(question.isAsking)
        question.selectionChanged(to: [])
        #expect(!question.isAsking)
    }

    /// A second confirmation while a removal runs starts nothing, and the removal counts as running until it ends.
    @Test func runsOneRemovalAtATime() {
        let question = RemovalQuestion()
        question.ask(first)

        #expect(question.start() == first)
        #expect(question.isRemoving)
        #expect(question.start() == nil)
        question.finish()
        #expect(!question.isRemoving)
    }

    /// A scan the page asks for while the question is up waits, and runs once the question is closed.
    @Test func aScanAskedForWhileTheQuestionIsUpWaitsUntilItCloses() {
        let question = RemovalQuestion()
        question.ask(first)

        #expect(!question.mayScan())
        #expect(!question.hasWaitingScan)
        question.isAsking = false
        #expect(question.hasWaitingScan)
        #expect(question.mayScan())
        #expect(!question.hasWaitingScan)
    }

    /// A scan asked for during a removal waits too, and the scan that ends the removal covers it.
    @Test func aScanAskedForDuringARemovalIsCoveredByTheScanThatEndsIt() {
        let question = RemovalQuestion()
        question.ask(first)
        _ = question.start()
        question.isAsking = false

        #expect(!question.mayScan())
        #expect(!question.hasWaitingScan)
        question.selectionChanged(to: [])
        #expect(question.isRemoving)
        question.finish()
        #expect(!question.hasWaitingScan)
        #expect(question.mayScan())
    }

    @Test func totalsWhatWasMeasuredAndSaysWhenSomethingWasNot() {
        let measured = URL(filePath: "/Users/me/Library/Caches/measured")
        let unknown = URL(filePath: "/Users/me/Library/Caches/unknown")

        #expect(RemovalRequest(urls: [measured], sizes: [measured: 100]).total == SizeTotal(known: 100, isComplete: true))
        #expect(RemovalRequest(urls: [measured, unknown], sizes: [measured: 100]).total == SizeTotal(known: 100, isComplete: false))
    }
}
