@testable import PeelCore
import Testing

/// Totals read back from a file or a preference any process can write: a sum past the largest number stops there
/// instead of stopping the app.
struct CappedSumTests {
    @Test func stopsAtTheLargestNumberInsteadOfTrapping() {
        #expect(Int.max.addingCapped(1) == .max)
        #expect((Int64.max - 1).addingCapped(Int64.max) == .max)
        #expect(Int.min.addingCapped(-1) == .min)
    }

    @Test func sumsASequenceUpToTheLargestNumber() {
        #expect([Int64.max, 1, 2].cappedSum == .max)
        #expect([Int64(40), 2].cappedSum == 42)
        #expect([Int64]().cappedSum == 0)
    }

    @Test func combinesTotalsUpToTheLargestNumber() {
        let whole = SizeTotal(combining: [
            SizeTotal(known: .max, isComplete: true), SizeTotal(known: 1, isComplete: true),
        ])
        #expect(whole == SizeTotal(known: .max, isComplete: true))
        let part = SizeTotal(combining: [
            SizeTotal(known: 10, isComplete: true), SizeTotal(known: 5, isComplete: false),
        ])
        #expect(part == SizeTotal(known: 15, isComplete: false))
    }

    @Test func addsAsUsualBelowTheLimit() {
        #expect(40.addingCapped(2) == 42)
        #expect(Int64(0).addingCapped(0) == 0)
        #expect(5.addingCapped(-3) == 2)
    }
}
