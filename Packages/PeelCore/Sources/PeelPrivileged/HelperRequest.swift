public import Darwin

/// The checks every request to the helper passes before any work, in the order they are made: what costs nothing
/// comes first, and the account behind the connection is asked last, once the request is known to be sound.
public enum HelperRequest {
    /// Limits on one request, so a client cannot hand the helper an unbounded amount of work. Each item the helper
    /// accepts keeps its folder open until the move ends, and launchd gives a daemon 256 descriptors
    /// (`launchctl limit maxfiles`), so the app sends its items in requests of this size. `PATH_MAX` counts the
    /// terminating NUL, so the longest real path is 1,023 bytes.
    public static let maximumItems = 100
    public static let maximumPathLength = 1_023

    public struct Caller: Sendable {
        public let user: uid_t
        public let homeDirectory: String

        public init(user: uid_t, homeDirectory: String) {
            self.user = user
            self.homeDirectory = homeDirectory
        }
    }

    public static func admit(
        version: Int,
        items: Int = 0,
        paths: [String] = [],
        caller: () -> Caller?
    ) -> Result<Caller, HelperRefusal> {
        guard version == HelperIdentity.protocolVersion else { return .failure(.outOfDate) }
        guard items <= maximumItems else { return .failure(.tooManyItems) }
        guard !paths.contains(where: isTooLong) else { return .failure(.pathTooLong) }
        guard let caller = caller() else { return .failure(.notAllowed) }
        return .success(caller)
    }

    public static func isTooLong(_ path: String) -> Bool {
        path.utf8.count > maximumPathLength
    }
}

extension HelperRefusal: Error {}
