@testable import PeelCore
import Testing

struct SizeTotalTests {
    @Test func addsUpWhatIsKnownAndSaysWhenThatIsNotAll() {
        #expect(SizeTotal([100, 20, 3]) == SizeTotal(known: 123, isComplete: true))
        #expect(SizeTotal([100, nil, 3]) == SizeTotal(known: 103, isComplete: false))
        #expect(SizeTotal([Int64?]()) == SizeTotal(known: 0, isComplete: true))
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
