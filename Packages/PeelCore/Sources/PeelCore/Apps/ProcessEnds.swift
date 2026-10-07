public import Foundation
import os

/// When running programs end, as the kernel tells it. AppKit's `NSRunningApplication.isTerminated` changes only once
/// AppKit hears of the end, which can be long after it.
public enum ProcessEnds {
    /// Each of `identifiers` as its process ends, at once for one that has ended already, watched from this call on.
    /// The stream finishes once every one has ended.
    public static func of(_ identifiers: [pid_t]) -> AsyncStream<pid_t> {
        AsyncStream { continuation in
            let running = Set(identifiers.filter { $0 > 0 })
            let waiting = OSAllocatedUnfairLock(initialState: running)
            let sources = running.map { identifier in
                let source = DispatchSource.makeProcessSource(
                    identifier: identifier,
                    eventMask: .exit,
                    queue: .global(qos: .userInitiated)
                )
                source.setEventHandler {
                    continuation.yield(identifier)
                    source.cancel()
                    if waiting.withLock({ $0.remove(identifier); return $0.isEmpty }) {
                        continuation.finish()
                    }
                }
                return source
            }
            continuation.onTermination = { _ in sources.forEach { $0.cancel() } }
            guard !sources.isEmpty else { return continuation.finish() }
            sources.forEach { $0.resume() }
        }
    }
}
