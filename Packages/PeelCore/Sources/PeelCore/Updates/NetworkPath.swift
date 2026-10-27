import Foundation
import Network
import Synchronization

enum NetworkPath {
    /// The first path the framework reports, or true when none comes within a second, so a check never waits on it.
    @concurrent
    static func isOnline() async -> Bool {
        let monitor = NWPathMonitor()
        let queue = DispatchQueue(label: "Peel.NetworkPath", qos: .userInitiated)
        let isOnline = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let answered = Mutex(false)
            let answer = { @Sendable (isOnline: Bool) in
                guard answered.withLock({ wasAnswered in
                    defer { wasAnswered = true }
                    return !wasAnswered
                }) else { return }
                continuation.resume(returning: isOnline)
            }
            monitor.pathUpdateHandler = { answer($0.status == .satisfied) }
            monitor.start(queue: queue)
            queue.asyncAfter(deadline: .now() + 1) { answer(true) }
        }
        monitor.cancel()
        return isOnline
    }
}
