/// Which of several overlapping checks of one thing may show its answer: each one as soon as it ends, unless a check
/// that started after it has shown its own, or the thing changed after it started. Waiting for the newest check alone
/// shows nothing for as long as each check outlasts the start of the next.
public struct OverlappingChecks: Sendable {
    public struct Check: Sendable {
        fileprivate let number: Int
        fileprivate let change: Int
    }

    private var started = 0
    private var shown = 0
    private var changes = 0

    public init() {}

    public mutating func start() -> Check {
        started += 1
        return Check(number: started, change: changes)
    }

    /// The thing checked changed, so no check started before now may show its answer.
    public mutating func changed() {
        changes += 1
    }

    public mutating func mayShow(_ check: Check) -> Bool {
        guard check.change == changes, check.number > shown else { return false }
        shown = check.number
        return true
    }
}
