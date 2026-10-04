import Darwin
import Synchronization

/// Signals a process ignores while some work runs. Ignored rather than blocked, since a signal blocked on one
/// thread still reaches the process through another. Runs may overlap: the first to begin sets the handlers
/// aside, and only the last to end gives each signal its handler back. A signal belongs to one such set.
public final class IgnoredSignals: Sendable {
    public let signals: [Int32]
    private let held = Mutex<(runs: Int, handlers: [sig_t?])>((0, []))

    public init(_ signals: [Int32]) {
        self.signals = signals
    }

    public func run<T>(_ work: () throws -> T) rethrows -> T {
        begin()
        defer { end() }
        return try work()
    }

    public func run<T>(_ work: () async throws -> T) async rethrows -> T {
        begin()
        defer { end() }
        return try await work()
    }

    private func begin() {
        held.withLock { held in
            if held.runs == 0 {
                held.handlers = signals.map { signal($0, SIG_IGN) }
            }
            held.runs += 1
        }
    }

    private func end() {
        held.withLock { held in
            held.runs -= 1
            if held.runs == 0 {
                for (number, handler) in zip(signals, held.handlers) {
                    signal(number, handler)
                }
            }
        }
    }
}
