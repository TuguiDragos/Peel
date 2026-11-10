import Darwin
import Foundation
@testable import PeelCore
import PeelPrivileged
import Synchronization

/// Who answers for a program a test starts through Peel, asked the moment the program names itself: it moves a file
/// holding its pid to `started` inside `folder`, then waits until `goOn` is there. The question runs on a queue of
/// its own, since a busy suite can hold a test's task past the time limit Peel gives the program, and a program
/// stopped by then answers -1.
final class ProgramStart: Sendable {
    typealias Answer = (pid: pid_t, responsible: pid_t)

    private let source: any DispatchSourceFileSystemObject
    private let answers: AsyncStream<Answer>
    private let sink: AsyncStream<Answer>.Continuation

    init(in folder: URL, started: URL, goOn: URL, system: Subprocess.Responsibility) throws {
        let descriptor = open(folder.path(percentEncoded: false), O_EVTONLY)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        (answers, sink) = AsyncStream.makeStream(of: Answer.self)
        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: .write, queue: DispatchQueue(label: "ProgramStart")
        )
        let asked = Mutex(false)
        source.setEventHandler { [sink] in
            guard let pid = (try? String(contentsOf: started, encoding: .utf8)).flatMap({
                pid_t($0.trimmingCharacters(in: .whitespacesAndNewlines))
            }), !asked.withLock({ $0 }) else { return }
            asked.withLock { $0 = true }
            sink.yield((pid, system.responsible(pid)))
            sink.finish()
            try? Data().write(to: goOn)
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
    }

    /// What was asked, or nil when the run ended before the program named itself.
    var answer: Answer? {
        get async { await answers.first { _ in true } }
    }

    /// Called once the run is over, so a program that never named itself ends the wait.
    func runEnded() {
        sink.finish()
        source.cancel()
    }
}
