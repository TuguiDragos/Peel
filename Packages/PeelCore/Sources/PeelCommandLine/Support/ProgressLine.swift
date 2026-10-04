import Darwin
import Dispatch
import PeelCore
import Synchronization

/// One line on standard error that says how far a long scan has got, written over itself as the scan goes on and
/// cleared once it ends, before the command prints anything else. Only a terminal shows it, and only while `peel`
/// is its foreground job: a script reading standard error, or a job sent to the background, gets nothing.
enum ProgressLine {
    /// Nothing is drawn in the first half second, so a quick scan leaves no flash behind.
    private static let firstDraw = DispatchTimeInterval.milliseconds(500)
    private static let redraw = DispatchTimeInterval.milliseconds(100)

    /// Runs a scan that counts what it reads (`ScanCount`), and shows how much it has read.
    static func counting<Answer>(
        on descriptor: Int32 = STDERR_FILENO,
        _ scan: () async throws -> Answer
    ) async rethrows -> Answer {
        let count = ScanCount()
        return try await showing({ lookedAt(count.value) }, on: descriptor) {
            try await ScanCount.$current.withValue(count) { try await scan() }
        }
    }

    /// Runs `work`, which tells `show` what the line says, and shows the newest of it.
    static func reporting<Answer>(
        on descriptor: Int32 = STDERR_FILENO,
        _ work: (_ show: @escaping @Sendable (String) -> Void) async throws -> Answer
    ) async rethrows -> Answer {
        let newest = Newest()
        return try await showing({ newest.text }, on: descriptor) {
            try await work { newest.text = $0 }
        }
    }

    /// What a scan that counts its reads says, in the app's words, once it has read something.
    static func lookedAt(_ read: Int) -> String? {
        read > 0 ? "Looked at \(Output.count(read, "item", "items"))" : nil
    }

    private static func showing<Answer>(
        _ text: @escaping @Sendable () -> String?,
        on descriptor: Int32,
        while work: () async throws -> Answer
    ) async rethrows -> Answer {
        guard isatty(descriptor) == 1 else { return try await work() }
        let line = Line(descriptor)
        let timer = DispatchSource.makeTimerSource(queue: line.queue)
        timer.setEventHandler { line.draw(text()) }
        timer.schedule(deadline: .now() + firstDraw, repeating: redraw)
        timer.activate()
        defer {
            // A canceled timer starts no new draw, and the queue holds the clear until a draw under way is done.
            timer.cancel()
            line.queue.sync { line.clear() }
        }
        return try await work()
    }
}

private final class Newest: Sendable {
    private let said = Mutex<String?>(nil)

    var text: String? {
        get { said.withLock { $0 } }
        set { said.withLock { $0 = newValue } }
    }
}

/// The line itself, drawn and cleared only on its own queue.
private final class Line: Sendable {
    let queue = DispatchQueue(label: "com.tuguidragos.Peel.CLI.progress")
    private let descriptor: Int32
    private let shown = Mutex("")

    init(_ descriptor: Int32) {
        self.descriptor = descriptor
    }

    func draw(_ text: String?) {
        guard let text, isTheForegroundJob else { return }
        // A line as wide as the terminal wraps, and a carriage return goes back only to the start of its last row.
        let width = columns.map { $0 - 1 } ?? .max
        let fitted = String(text.prefix(max(width, 0)))
        shown.withLock { shown in
            guard fitted != shown else { return }
            write("\r" + fitted + String(repeating: " ", count: max(min(shown.count, width) - fitted.count, 0)))
            shown = fitted
        }
    }

    func clear() {
        shown.withLock { shown in
            guard !shown.isEmpty, isTheForegroundJob else { return }
            write("\r" + String(repeating: " ", count: shown.count) + "\r")
            shown = ""
        }
    }

    /// A job in the background would draw over what is being typed in front of it. A terminal that is not this
    /// process's own has no foreground job to ask about (`tcgetpgrp(3)`), and is drawn on.
    private var isTheForegroundJob: Bool {
        let foreground = tcgetpgrp(descriptor)
        return foreground < 0 || foreground == getpgrp()
    }

    private var columns: Int? {
        var size = winsize()
        guard withUnsafeMutablePointer(to: &size, { ioctl(descriptor, TIOCGWINSZ, $0) }) == 0, size.ws_col > 0 else {
            return nil
        }
        return Int(size.ws_col)
    }

    private func write(_ text: String) {
        var bytes = Array(text.utf8)[...]
        while !bytes.isEmpty {
            let written = bytes.withUnsafeBytes { Darwin.write(descriptor, $0.baseAddress, $0.count) }
            if written > 0 {
                bytes = bytes.dropFirst(written)
            } else if written < 0, errno == EINTR {
                continue
            } else {
                return
            }
        }
    }
}
