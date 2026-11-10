extension FixedWidthInteger {
    /// The sum, or the largest (or smallest) value the type holds when the sum would go past it. For totals built
    /// from numbers any process can write, such as History's file or a preference, where `+` would stop the app.
    public func addingCapped(_ other: Self) -> Self {
        let (sum, overflowed) = addingReportingOverflow(other)
        guard overflowed else { return sum }
        return other < 0 ? .min : .max
    }

    /// The product, capped the same way: for the sizes a disk reports in blocks, which any server can make up.
    public func multipliedCapped(by other: Self) -> Self {
        let (product, overflowed) = multipliedReportingOverflow(by: other)
        guard overflowed else { return product }
        return (self < 0) == (other < 0) ? .max : .min
    }
}

extension Sequence where Element: FixedWidthInteger {
    /// The sum of the elements, capped as `addingCapped` caps it.
    public var cappedSum: Element {
        reduce(0) { $0.addingCapped($1) }
    }
}
