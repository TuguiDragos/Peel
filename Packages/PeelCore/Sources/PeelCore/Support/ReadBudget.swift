import Foundation

/// The end of a read's budget. While macOS asks the person whether Peel may read another app's data, the read it
/// holds waits for that answer, so the budget starts again rather than give up what the answer may allow.
enum ReadBudget {
    /// Calls `wake` once `budget` has run out, unless `isWaiting` says nobody waits anymore.
    static func end(
        after budget: TimeInterval,
        while isAsked: @escaping @Sendable () -> Bool = AppDataQuestion.isOnScreen,
        isWaiting: @escaping @Sendable () -> Bool,
        then wake: @escaping @Sendable () -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + budget) {
            guard isWaiting() else { return }
            if isAsked() {
                end(after: budget, while: isAsked, isWaiting: isWaiting, then: wake)
            } else {
                wake()
            }
        }
    }
}
