import Darwin
import PeelCore

/// Keeps `peel` running from a move, or a put back, until History records it: stopped in between, History would miss
/// what moved, or keep listing what went back.
enum Uninterrupted {
    /// What would stop `peel` there: Ctrl-C, a kill, a terminal closing or an SSH connection dropping, Ctrl-\, and
    /// output piped into a command that has quit.
    static let signals = [SIGINT, SIGTERM, SIGHUP, SIGQUIT, SIGPIPE]

    private static let ignored = IgnoredSignals(signals)

    /// Runs `work` with `signals` ignored.
    static func run<T>(_ work: () async throws -> T) async rethrows -> T {
        try await ignored.run(work)
    }
}
