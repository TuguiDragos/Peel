import Foundation

/// Room on the stack for work that goes a step deeper for each level of what it reads, where a thread of Swift's
/// pool has half a megabyte.
enum DeepStack {
    /// Runs `work` on a thread of its own whose stack is `megabytes` large, at the priority of whoever asks. What
    /// `work` makes and lets go of is freed there too, before the answer comes back.
    static func run<Value: Sendable>(megabytes: Int, _ work: @escaping @Sendable () -> Value) async -> Value {
        let quality = QualityOfService(Task.currentPriority)
        return await withCheckedContinuation { continuation in
            let thread = Thread { continuation.resume(returning: autoreleasepool(invoking: work)) }
            thread.stackSize = megabytes << 20
            thread.qualityOfService = quality
            thread.start()
        }
    }
}
