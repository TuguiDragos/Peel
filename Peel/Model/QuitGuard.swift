import AppKit

/// What a quit waits for: a removal from its first move until History has it, a Put Back until it is done, and a
/// Homebrew command that changes something. Quitting halfway would leave what already moved in History as an
/// interrupted removal, without its name or sizes, skip what follows a move (stopping a job whose file went,
/// forgetting its settings), leave items put back listed as still in the Trash, and leave Homebrew with nowhere to
/// write, so it stops at its next line.
@MainActor
final class QuitGuard {
    static let shared = QuitGuard()

    private var running = 0
    private var refusing = 0
    private var isQuitWaiting = false
    /// What stops each piece of work under way that can be stopped, by its own number.
    private var stops: [Int: @MainActor () -> Void] = [:]
    private var nextNumber = 0
    private let asksToStop: @MainActor () -> Bool
    private let answer: @MainActor (Bool) -> Void

    init(
        asksToStop: @escaping @MainActor () -> Bool = QuitGuard.askToStop,
        answer: @escaping @MainActor (Bool) -> Void = { NSApp.reply(toApplicationShouldTerminate: $0) }
    ) {
        self.asksToStop = asksToStop
        self.answer = answer
    }

    /// Runs `work`, and a quit asked meanwhile waits for it to end. Work that can take long, such as a Homebrew
    /// upgrade, passes `stop`, which a quit calls once the person agrees to stop it.
    func run<T, Failure: Error>(
        stoppingWith stop: (@MainActor () -> Void)? = nil,
        _ work: () async throws(Failure) -> T
    ) async throws(Failure) -> T {
        running += 1
        let number = nextNumber
        nextNumber += 1
        stops[number] = stop
        defer {
            stops[number] = nil
            running -= 1
            if running == 0, isQuitWaiting {
                isQuitWaiting = false
                answer(true)
            }
        }
        return try await work()
    }

    /// Whether a removal, a Put Back or a Homebrew command is under way.
    var hasWorkUnderWay: Bool { running > 0 }

    /// Runs Peel's removal of itself, which ends Peel its own way, so a quit asked meanwhile is refused. Quitting
    /// through AppKit would write the window's place and Peel's settings again, just after they went to the Trash.
    func runRefusingQuit<T>(_ work: () async -> T) async -> T {
        refusing += 1
        defer { refusing -= 1 }
        return await work()
    }

    /// The answer to a quit: now when nothing is under way, otherwise once the last of it ends. Work that can be
    /// stopped is stopped only on the person's word, and a quit they decline is cancelled.
    func replyToQuit() -> NSApplication.TerminateReply {
        guard refusing == 0 else { return .terminateCancel }
        guard running > 0 else { return .terminateNow }
        if !stops.isEmpty {
            guard asksToStop() else { return .terminateCancel }
            stops.values.forEach { $0() }
        }
        isQuitWaiting = true
        return .terminateLater
    }

    static func askToStop() -> Bool {
        let alert = NSAlert()
        alert.messageText = String(localized: "Homebrew is still upgrading.")
        alert.informativeText = String(localized: "If you quit now, Homebrew stops, and a package it is in the middle of installing may be left half installed. A cask’s app can stay in Homebrew’s folder until you reinstall the cask.")
        alert.addButton(withTitle: String(localized: "Keep Peel Open"))
        alert.addButton(withTitle: String(localized: "Stop and Quit")).hasDestructiveAction = true
        return alert.runModal() == .alertSecondButtonReturn
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
