/// A sum of sizes, some of which may be unknown. An unknown size is never counted as zero: it marks the
/// total incomplete.
public struct SizeTotal: Sendable, Hashable, Comparable {
    public let known: Int64
    /// False when some size is unknown, so `known` is only the least the total can be.
    public let isComplete: Bool

    public init(known: Int64, isComplete: Bool) {
        self.known = known
        self.isComplete = isComplete
    }

    /// Reads `sizes` once, so a sequence that can be read only once is summed whole. The sum stops at `Int64.max`
    /// rather than trapping, since some sizes come from a file any process can rewrite.
    public init(_ sizes: some Sequence<Int64?>) {
        var known: Int64 = 0
        var isComplete = true
        for size in sizes {
            if let size { known = known.addingCapped(size) } else { isComplete = false }
        }
        self.init(known: known, isComplete: isComplete)
    }

    /// How the total reads: a size, the least it can be, or nothing known at all.
    public enum Reading: Sendable, Hashable {
        case exactly(Int64)
        case atLeast(Int64)
        case unknown
    }

    public var reading: Reading {
        if isComplete { return .exactly(known) }
        return known > 0 ? .atLeast(known) : .unknown
    }

    /// An incomplete total counts as larger than a complete one, since what ran out of time is most likely the biggest.
    public static func < (lhs: SizeTotal, rhs: SizeTotal) -> Bool {
        lhs.isComplete != rhs.isComplete ? lhs.isComplete : lhs.known < rhs.known
    }
}
