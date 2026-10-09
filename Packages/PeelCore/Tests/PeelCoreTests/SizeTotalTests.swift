import Foundation
@testable import PeelCore
import Testing

struct SizeTotalTests {
    /// A total with nothing measured is unknown, never zero: two folders that did not answer are not two empty files.
    @Test func readsAsExactAtLeastOrUnknown() {
        #expect(SizeTotal([100, 20]).reading == .exactly(120))
        #expect(SizeTotal([Int64?]()).reading == .exactly(0))
        #expect(SizeTotal([100, nil]).reading == .atLeast(100))
        #expect(SizeTotal([nil, nil]).reading == .unknown)
    }

    @Test func addsUpWhatIsKnownAndSaysWhenThatIsNotAll() {
        #expect(SizeTotal([100, 20, 3]) == SizeTotal(known: 123, isComplete: true))
        #expect(SizeTotal([100, nil, 3]) == SizeTotal(known: 103, isComplete: false))
        #expect(SizeTotal([Int64?]()) == SizeTotal(known: 0, isComplete: true))
    }

    /// Moving a folder takes what is inside it, so an item inside another of the same move frees nothing more, even
    /// when its own size was not measured. A folder whose name only begins another's holds nothing of it.
    @Test func countsAnItemInsideAnotherMovedItemOnce() {
        let steam = URL(filePath: "/Users/me/Library/Application Support/Steam")
        let bundle = steam.appending(path: "Steam.AppBundle")
        let caches = URL(filePath: "/Users/me/Library/Caches/Steam")
        #expect(
            SizeTotal(movingItemsAt: [steam: 800, bundle: 700, caches: 5]) == SizeTotal(known: 805, isComplete: true)
        )
        #expect(SizeTotal(movingItemsAt: [steam: 800, bundle: nil]) == SizeTotal(known: 800, isComplete: true))
        let beside = URL(filePath: "/Users/me/Library/Application Support/Steam 2")
        #expect(SizeTotal(movingItemsAt: [steam: 800, beside: 2]) == SizeTotal(known: 802, isComplete: true))
    }

    /// Sizes can come from a sequence that is read once, as they are measured. An unknown one must still make
    /// the total incomplete: reading the sequence a second time would find it empty.
    @Test func readsTheSizesOnce() {
        final class ReadOnce: Sequence, IteratorProtocol {
            private var sizes: [Int64?]
            init(_ sizes: [Int64?]) { self.sizes = sizes }
            func next() -> Int64?? {
                guard !sizes.isEmpty else { return .none }
                return .some(sizes.removeFirst())
            }
        }

        #expect(SizeTotal(ReadOnce([100, nil, 3])) == SizeTotal(known: 103, isComplete: false))
    }

    /// A folder that ran out of time is most likely the biggest one, so it is listed where the biggest go.
    @Test func putsWhatIsNotKnownAheadOfTheBiggest() {
        let totals = [SizeTotal([5]), SizeTotal([nil]), SizeTotal([9_000_000]), SizeTotal([7, nil])]
        #expect(totals.sorted(by: >) == [SizeTotal([7, nil]), SizeTotal([nil]), SizeTotal([9_000_000]), SizeTotal([5])])
    }
}
