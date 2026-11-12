import Darwin
import os

/// What the helper writes to the unified log: a line for each request, with its account and what came of it, and one
/// for each item it left where it was. That item's path stays private there, as the log keeps it; a request names
/// only a daemon, by its label or its file, and the reasons are Peel's own.
enum HelperLog {
    private static let requests = Logger(subsystem: HelperIdentity.helperIdentifier, category: "Requests")

    static func note(_ request: String, for account: uid_t?, _ outcome: String) {
        let who = asked(request, by: account)
        requests.notice("\(who, privacy: .public): \(outcome, privacy: .public)")
    }

    static func left(_ path: String, by request: String, for account: uid_t?, because reason: String) {
        let who = asked(request, by: account)
        requests.notice("\(who, privacy: .public) left \(path, privacy: .private): \(reason, privacy: .public)")
    }

    private static func asked(_ request: String, by account: uid_t?) -> String {
        "\(request) for account \(account.map { String($0) } ?? "unknown")"
    }
}
