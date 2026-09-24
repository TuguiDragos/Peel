import Foundation
import SQLite3

/// Reads the user's TCC database, where macOS records privacy decisions. Only a process with Full Disk Access
/// can open it, so anything unreadable is unknown. It is opened read-only and never written. Its location and
/// table are not API, so its answer is only a hint: what a real removal shows takes precedence (`HomeModel`).
/// Rows are matched by bundle identifier alone, while macOS also checks the signature a permission was given to.
enum PrivacyDatabase {
    static var userDatabase: String {
        NSHomeDirectory() + "/Library/Application Support/com.apple.TCC/TCC.db"
    }

    /// Returns the decision for `client` on `service`. An `auth_value` of 0 means denied and 2 means allowed.
    /// Any other value, such as partial access, is unknown.
    static func decision(on service: String, for client: String, in database: String = userDatabase) -> AccessState {
        var handle: OpaquePointer?
        guard sqlite3_open_v2(database, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(handle)
            return .unknown
        }
        defer { sqlite3_close(handle) }

        var statement: OpaquePointer?
        let query = "SELECT auth_value FROM access WHERE service = ? AND client = ? AND client_type = 0"
        guard sqlite3_prepare_v2(handle, query, -1, &statement, nil) == SQLITE_OK else { return .unknown }
        defer { sqlite3_finalize(statement) }

        // `SQLITE_TRANSIENT`, which Swift can't import. SQLite copies the text, since the C strings Swift
        // passes last only for the call.
        let copied = unsafeBitCast(-1, to: (@convention(c) (UnsafeMutableRawPointer?) -> Void).self)
        sqlite3_bind_text(statement, 1, service, -1, copied)
        sqlite3_bind_text(statement, 2, client, -1, copied)
        guard sqlite3_step(statement) == SQLITE_ROW else { return .unknown }
        return switch sqlite3_column_int(statement, 0) {
        case 0: .missing
        case 2: .granted
        default: .unknown
        }
    }
}
