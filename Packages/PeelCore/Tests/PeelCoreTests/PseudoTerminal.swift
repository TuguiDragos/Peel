import Darwin
import Foundation

/// A pseudo terminal, the kind a Terminal window is: what a program writes on its replica is read here as the window
/// would draw it, and what is typed reaches the program as keys.
final class PseudoTerminal {
    let replica: Int32
    private let primary: Int32
    private(set) var drawn = ""

    init(columns: UInt16 = 80) throws {
        var primary: Int32 = 0
        var replica: Int32 = 0
        var size = winsize(ws_row: 24, ws_col: columns, ws_xpixel: 0, ws_ypixel: 0)
        guard openpty(&primary, &replica, nil, nil, &size) == 0 else { throw POSIXError(.EAGAIN) }
        self.primary = primary
        self.replica = replica
    }

    deinit {
        close(replica)
        close(primary)
    }

    func type(_ text: String) {
        _ = text.utf8CString.withUnsafeBufferPointer { Darwin.write(primary, $0.baseAddress, $0.count - 1) }
    }

    /// Reads until `text` has been drawn, giving up after ten seconds.
    func read(until text: String) {
        let end = ContinuousClock.now + .seconds(10)
        while !drawn.contains(text), ContinuousClock.now < end {
            readMore(waiting: 100)
        }
    }

    /// Everything drawn, once nothing more has come for a third of a second.
    func everything() -> String {
        while readMore(waiting: 300) {}
        return drawn
    }

    @discardableResult
    private func readMore(waiting milliseconds: Int32) -> Bool {
        var ready = pollfd(fd: primary, events: Int16(POLLIN), revents: 0)
        guard poll(&ready, 1, milliseconds) > 0 else { return false }
        var buffer = [UInt8](repeating: 0, count: 4_096)
        let count = Darwin.read(primary, &buffer, buffer.count)
        guard count > 0 else { return false }
        drawn += String(decoding: buffer[0..<count], as: UTF8.self)
        return true
    }
}
