public import Darwin
public import Foundation

/// The checks every request to the helper passes before any work, in the order they are made: what costs nothing
/// comes first, and the account behind the connection is asked last, once the request is known to be sound.
public enum HelperRequest {
    /// Limits on one request, so a client cannot hand the helper an unbounded amount of work. Each item the helper
    /// accepts keeps its folder open until the move ends, and launchd gives a daemon 256 descriptors
    /// (`launchctl limit maxfiles`), so the app sends its items in requests of this size. `PATH_MAX` counts the
    /// terminating NUL, so the longest real path is 1,023 bytes.
    public static let maximumItems = 100
    public static let maximumPathLength = 1_023
    /// How long the helper works on one request's items: it begins nothing after this and answers with what it got
    /// to, well before the app stops waiting for the answer, so nothing it moves goes untold.
    public static let timeToMove: TimeInterval = 90

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
        caller: () -> Result<Caller, HelperRefusal>
    ) -> Result<Caller, HelperRefusal> {
        guard version == HelperIdentity.protocolVersion else { return .failure(.outOfDate) }
        guard items <= maximumItems else { return .failure(.tooManyItems) }
        guard !paths.contains(where: isTooLong) else { return .failure(.pathTooLong) }
        return caller()
    }

    /// The account the helper serves a request for, with its home folder, which the helper's rules need.
    public static func caller(
        user: uid_t?,
        approval: Data,
        isAdministrator: (uid_t) -> Bool = UserAuthorization.isAdministrator,
        isApproved: (Data) -> Bool = AdministratorAuthorization.isGranted(by:),
        homeDirectory: (uid_t) -> String? = UserAuthorization.homeDirectory(of:)
    ) -> Result<Caller, HelperRefusal> {
        guard let user, let home = homeDirectory(user) else { return .failure(.notAllowed) }
        // An administrator is served as one, and only another account's approval costs a question to macOS.
        guard isAdministrator(user) || isApproved(approval) else { return .failure(.notAuthorized) }
        return .success(Caller(user: user, homeDirectory: home))
    }

    public static func isTooLong(_ path: String) -> Bool {
        path.utf8.count > maximumPathLength
    }
}

extension HelperRefusal: Error {}
