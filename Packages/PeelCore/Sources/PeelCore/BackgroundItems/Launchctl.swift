import Foundation
import PeelPrivileged

enum Launchctl {
    struct JobDetails: Equatable {
        var path: String?
        var program: String?
        var managedBy: String?
        var parentBundleIdentifier: String?
    }

    /// Runs `launchctl` and returns its exit status and its output, error text included. `bootout` waits for
    /// the job to exit, and a job that ignores the signal keeps it waiting for launchd's own time limit. A
    /// removal waits on this call, so each call gets 30 seconds at most.
    @concurrent
    static func run(_ arguments: [String]) async -> (status: Int32, output: String) {
        switch await Subprocess.run("/bin/launchctl", arguments, timeout: 30) {
        case .success(let output): (output.status, output.text + output.errorText)
        case .failure(let failure): (-1, failure.explanation)
        }
    }

    /// Parses `launchctl list`: "PID\tStatus\tLabel", where PID is "-" for jobs that aren't running. Nil when the
    /// output does not start with that header, since another form says nothing.
    static func parseList(_ output: String) -> [String: Int32?]? {
        let lines = output.split(whereSeparator: \.isNewline)
        guard lines.first == "PID\tStatus\tLabel" else { return nil }
        var jobs: [String: Int32?] = [:]
        for line in lines.dropFirst() {
            let columns = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard columns.count == 3 else { continue }
            jobs[String(columns[2])] = Int32(columns[0])
        }
        return jobs
    }

    /// Parses the "services = { … }" block of `launchctl print system`: "pid exit-status label". Nil when there is
    /// no such block.
    static func parseSystemServices(_ output: String) -> [String: Int32?]? {
        var jobs: [String: Int32?]?
        for line in output.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "services = {" {
                jobs = [:]
                continue
            }
            guard jobs != nil else { continue }
            if trimmed == "}" { break }
            let columns = trimmed.split(whereSeparator: \.isWhitespace)
            guard columns.count >= 3 else { continue }
            jobs?[columns[2...].joined(separator: " ")] = Int32(columns[0]).flatMap { $0 > 0 ? $0 : nil }
        }
        return jobs
    }

    /// Parses the `"label" => disabled|enabled` lines of a "disabled services = { … }" block. Nil when there is no
    /// such block.
    static func parseDisabled(_ output: String) -> [String: Bool]? {
        var overrides: [String: Bool]?
        for line in output.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "disabled services = {" {
                overrides = [:]
                continue
            }
            guard overrides != nil else { continue }
            if trimmed == "}" { break }
            // Finds the last arrow after the opening quote, because a label can contain an arrow of its own. The
            // quote is checked first: a label can hold a line break, which leaves a line with nothing after the tabs.
            guard trimmed.hasPrefix("\"") else { continue }
            let afterQuote = trimmed.index(after: trimmed.startIndex)..<trimmed.endIndex
            guard let arrow = trimmed.range(of: "\" => ", options: .backwards, range: afterQuote) else { continue }
            let label = String(trimmed[trimmed.index(after: trimmed.startIndex)..<arrow.lowerBound])
            overrides?[label] = trimmed[arrow.upperBound...].hasPrefix("disabled")
        }
        return overrides
    }

    /// Parses the top-level "key = value" lines of `launchctl print <domain>/<label>`.
    static func parseDetails(_ output: String) -> JobDetails {
        var details = JobDetails()
        for line in output.split(whereSeparator: \.isNewline) where line.hasPrefix("\t") && !line.hasPrefix("\t\t") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let separator = trimmed.range(of: " = ") else { continue }
            let key = trimmed[..<separator.lowerBound]
            let value = String(trimmed[separator.upperBound...])
            switch key {
            case "path": details.path = value
            case "program": details.program = value
            case "managed_by": details.managedBy = value
            case "parent bundle identifier": details.parentBundleIdentifier = value
            default: break
            }
        }
        return details
    }
}
