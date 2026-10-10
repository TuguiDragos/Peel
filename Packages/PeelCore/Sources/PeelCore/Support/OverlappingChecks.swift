/// Which of several overlapping checks of one thing may show its answer: each one as soon as it ends, unless a check
/// that started after it has shown its own, or the thing changed after it started. Waiting for the newest check alone
/// shows nothing for as long as each check outlasts the start of the next. While the thing changes, what a check finds
/// is neither the old thing nor the new one, so nothing shows until the change ends.
public struct OverlappingChecks: Sendable {
    public struct Check: Sendable {
        fileprivate let number: Int
        fileprivate let change: Int
    }

    private var started = 0
    private var shown = 0
    private var changes = 0
    private var isChanging = false

    public init() {}

    public mutating func start() -> Check {
        started += 1
        return Check(number: started, change: changes)
    }

    public mutating func changeStarts() {
        isChanging = true
    }

    public mutating func changeEnds() {
        changes += 1
        isChanging = false
    }

    public mutating func mayShow(_ check: Check) -> Bool {
        guard !isChanging, check.change == changes, check.number > shown else { return false }
        shown = check.number
        return true
    }
}
