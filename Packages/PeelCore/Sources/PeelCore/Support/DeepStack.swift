import Foundation
import Synchronization

/// Room on the stack for work that goes a step deeper for each level of what it reads, where a thread of Swift's
/// pool has half a megabyte.
enum DeepStack {
    /// Runs `work` on a thread of its own whose stack is `megabytes` large, at the priority of whoever asks, and
    /// waits for its answer. What `work` makes and lets go of is freed there too, before the answer comes back.
    static func run<Value: Sendable>(megabytes: Int, _ work: @escaping @Sendable () -> Value) -> Value {
        let answer = Mutex<Value?>(nil)
        let done = DispatchSemaphore(value: 0)
        let thread = Thread {
            let value = autoreleasepool(invoking: work)
            answer.withLock { $0 = value }
            done.signal()
        }
        thread.stackSize = megabytes << 20
        thread.qualityOfService = QualityOfService(Task.currentPriority)
        thread.start()
        done.wait()
        return answer.withLock { $0 }!
    }
}
