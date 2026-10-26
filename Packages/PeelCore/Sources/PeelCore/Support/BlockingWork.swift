import Foundation

/// Runs work that may wait in the kernel, such as reads on a network volume that stopped answering, on a queue of its
/// own rather than on the threads Swift's tasks share, as `SlowRead` does with a thread, at a fraction of its cost per
/// item and with no budget. The task waits until the work answers or the task is canceled; the work can check
/// `isGivenUp` and stop, and whatever it gives after that is dropped.
enum BlockingWork {
    private static let queue = DispatchQueue(
        label: "com.tuguidragos.Peel.blocking-work", qos: .userInitiated, attributes: .concurrent
    )

    static func run<T: Sendable>(
        _ work: @escaping @Sendable (_ isGivenUp: @escaping @Sendable () -> Bool) -> T
    ) async -> T? {
        guard !Task.isCancelled else { return nil }
        let answer = SlowRead.Answer<T>()
        queue.async { answer.give(work { answer.isGivenUp }) }
        return await answer.wait(nil)
    }
}
