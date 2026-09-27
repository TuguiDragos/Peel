import AppKit

/// What a quit waits for: a removal from its first move until History has it, and a Put Back until it is done.
/// Quitting halfway would leave what already moved in History as an interrupted removal, without its name or sizes,
/// skip what follows a move (stopping a job whose file went, forgetting its settings), and leave items put back
/// listed as still in the Trash.
@MainActor
final class QuitGuard {
    static let shared = QuitGuard()

    private var running = 0
    private var refusing = 0
    private var isQuitWaiting = false

    /// Runs `work`, and a quit asked meanwhile waits for it to end.
    func run<T, Failure: Error>(_ work: () async throws(Failure) -> T) async throws(Failure) -> T {
        running += 1
        defer {
            running -= 1
            if running == 0, isQuitWaiting {
                isQuitWaiting = false
                NSApp.reply(toApplicationShouldTerminate: true)
            }
        }
        return try await work()
    }

    /// Runs Peel's removal of itself, which ends Peel its own way, so a quit asked meanwhile is refused. Quitting
    /// through AppKit would write the window's place and Peel's settings again, just after they went to the Trash.
    func runRefusingQuit<T>(_ work: () async -> T) async -> T {
        refusing += 1
        defer { refusing -= 1 }
        return await work()
    }

    /// The answer to a quit: now when nothing is under way, otherwise once the last of it ends.
    func replyToQuit() -> NSApplication.TerminateReply {
        guard refusing == 0 else { return .terminateCancel }
        guard running > 0 else { return .terminateNow }
        isQuitWaiting = true
        return .terminateLater
    }

    /// Asks Peel to quit from the run loop rather than from inside the task that asks. The loop AppKit runs while a
    /// quit waits takes the main queue's next block only once the running one returns, so a quit asked from inside
    /// one would hold back the very work it waits for.
    static func quit() {
        RunLoop.main.perform {
            MainActor.assumeIsolated { NSApp.terminate(nil) }
        }
    }
}
