import Darwin
import Synchronization

/// Keeps `peel` running from a move, or a put back, until History records it: stopped in between, History would miss
/// what moved, or keep listing what went back.
enum Uninterrupted {
    /// What would stop `peel` there: Ctrl-C, a kill, a terminal closing or an SSH connection dropping, Ctrl-\, and
    /// output piped into a command that has quit.
    static let signals = [SIGINT, SIGTERM, SIGHUP, SIGQUIT, SIGPIPE]

    /// How many runs are under way, and the handlers the signals had before the first of them.
    private static let held = Mutex<(runs: Int, handlers: [sig_t?])>((0, []))

    /// Runs `work` with `signals` ignored. Ignored rather than blocked, since a signal blocked on one thread still
    /// stops the process through another. Only the last run to end gives each signal its handler back.
    static func run<T>(_ work: () async throws -> T) async rethrows -> T {
        held.withLock { held in
            if held.runs == 0 {
                held.handlers = signals.map { signal($0, SIG_IGN) }
            }
            held.runs += 1
        }
        defer {
            held.withLock { held in
                held.runs -= 1
                if held.runs == 0 {
                    for (number, handler) in zip(signals, held.handlers) {
                        signal(number, handler)
                    }
                }
            }
        }
        return try await work()
    }
}
