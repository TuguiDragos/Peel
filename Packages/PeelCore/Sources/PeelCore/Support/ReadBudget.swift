import Foundation

/// The end of a read's budget. While macOS asks the person whether Peel may read another app's data, the read it
/// holds waits for that answer, so the time the question is on screen doesn't count toward the budget.
enum ReadBudget {
    /// How often the time left is counted again: a question that comes and goes between two looks costs at most this.
    static let step: TimeInterval = 0.5

    /// Calls `wake` once `budget` of time without macOS's question has passed, unless `isWaiting` says nobody waits
    /// anymore.
    static func end(
        after budget: TimeInterval,
        while isAsked: @escaping @Sendable () -> Bool = AppDataQuestion.isOnScreen,
        isWaiting: @escaping @Sendable () -> Bool,
        then wake: @escaping @Sendable () -> Void
    ) {
        let wait = min(step, budget)
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + wait) {
            guard isWaiting() else { return }
            let left = isAsked() ? budget : budget - wait
            if left > 0 {
                end(after: left, while: isAsked, isWaiting: isWaiting, then: wake)
            } else {
                wake()
            }
        }
    }
}
