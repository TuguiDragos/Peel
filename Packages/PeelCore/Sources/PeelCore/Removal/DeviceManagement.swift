import Foundation
internal import PeelPrivileged
import Synchronization

/// Whether a device management service enrolled this Mac, which `profiles status -type enrollment` says without an
/// administrator (`man profiles`). Asked once, and only when Peel finds an agent a person can also install for
/// themselves, since whose it is then depends on the answer.
public enum DeviceManagement {
    public enum Enrollment: Sendable, Hashable {
        case enrolled
        case notEnrolled
    }

    /// What `profiles` answered: nil until it is asked, and when its answer can't be read.
    public static var enrollment: Enrollment? {
        if let standIn { return standIn.answer }
        return asked.withLock { $0 ?? nil }
    }

    /// The answer once `profiles` was asked, itself nil when it couldn't be read.
    private static let asked = Mutex<Enrollment??>(nil)

    /// Asks `profiles`, once for the whole process.
    @concurrent
    static func ask() async {
        guard standIn == nil, asked.withLock({ $0 == nil }) else { return }
        let answer = await read(within: 10)
        asked.withLock { if $0 == nil { $0 = .some(answer) } }
    }

    /// What `profiles` says now, or nil when it doesn't answer within `timeout` or its answer can't be read.
    @concurrent
    static func read(within timeout: TimeInterval?) async -> Enrollment? {
        let arguments = ["status", "-type", "enrollment"]
        return switch await Subprocess.run("/usr/bin/profiles", arguments, timeout: timeout) {
        case .success(let result) where result.status == 0:
            enrollment(in: String(decoding: result.standardOutput, as: UTF8.self))
        default: nil
        }
    }

    /// Reads the line `profiles` writes, "MDM enrollment: No", or "Yes" and the kind of enrollment.
    static func enrollment(in output: String?) -> Enrollment? {
        let label = "MDM enrollment:"
        guard let line = output?.split(separator: "\n").first(where: { $0.hasPrefix(label) }) else { return nil }
        let value = line.dropFirst(label.count).trimmingCharacters(in: .whitespaces)
        if value == "No" { return .notEnrolled }
        return value.hasPrefix("Yes") ? .enrolled : nil
    }

    struct StandIn: Sendable {
        let answer: Enrollment?
    }

    /// A test's answer in place of this Mac's, since no test can enroll the Mac.
    @TaskLocal static var standIn: StandIn?
}
