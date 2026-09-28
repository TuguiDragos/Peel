extension FixedWidthInteger {
    /// The sum, or the largest (or smallest) value the type holds when the sum would go past it. For totals built
    /// from numbers any process can write, such as History's file or a preference, where `+` would stop the app.
    public func addingCapped(_ other: Self) -> Self {
        let (sum, overflowed) = addingReportingOverflow(other)
        guard overflowed else { return sum }
        return other < 0 ? .min : .max
    }
}

extension Sequence where Element: FixedWidthInteger {
    /// The sum of the elements, capped as `addingCapped` caps it.
    public var cappedSum: Element {
        reduce(0) { $0.addingCapped($1) }
    }
}
