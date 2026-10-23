public import Foundation
import os

/// When running programs end, as the kernel tells it. AppKit's `NSRunningApplication.isTerminated` changes only once
/// AppKit hears of the end, which can be long after it.
public enum ProcessEnds {
    /// Whether the process still runs, as the kernel says: false from the moment it ends, before its parent has
    /// collected it and before AppKit hears of its end.
    public static func isRunning(_ identifier: pid_t) -> Bool {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        return proc_pidinfo(identifier, PROC_PIDTBSDINFO, 0, &info, size) == size
    }

    /// When the process started, as the kernel says, or nil when no such process runs. `sysctl` tells it of any
    /// process, root's included, while `proc_pidinfo` answers only about this account's.
    static func startTime(of identifier: pid_t) -> Date? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size
        var name = [CTL_KERN, KERN_PROC, KERN_PROC_PID, identifier]
        guard sysctl(&name, u_int(name.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
        let start = info.kp_proc.p_un.__p_starttime
        return Date(timeIntervalSince1970: TimeInterval(start.tv_sec) + TimeInterval(start.tv_usec) / 1_000_000)
    }

    /// Whether the process ends within `limit` seconds, true at once for one that has ended already. Any process may
    /// watch another one end, root's included (`kevent(2)`, EVFILT_PROC). The end and the deadline both arrive on
    /// dispatch: a task watching the end could wait for a thread of Swift's pool until the deadline had passed.
    public static func ends(_ identifier: pid_t, within limit: TimeInterval) async -> Bool {
        guard identifier > 0 else { return false }
        return await withCheckedContinuation { continuation in
            let resumed = OSAllocatedUnfairLock(initialState: false)
            let source = DispatchSource.makeProcessSource(
                identifier: identifier,
                eventMask: .exit,
                queue: .global(qos: .userInitiated)
            )
            let finish: @Sendable (Bool) -> Void = { ended in
                let isFirst = resumed.withLock { resumed in
                    defer { resumed = true }
                    return !resumed
                }
                guard isFirst else { return }
                source.cancel()
                continuation.resume(returning: ended)
            }
            source.setEventHandler { finish(true) }
            source.resume()
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + limit) { finish(false) }
        }
    }

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
