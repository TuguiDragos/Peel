/// Why a check of an app's own source learned nothing: who was asked, and what came back instead of an answer.
public struct UpdateFailure: Sendable, Hashable, Codable {
    public enum Asked: Sendable, Hashable, Codable {
        case appStore
        /// A server the app's own feed names, by host name.
        case server(String)
    }

    public enum Cause: Sendable, Hashable, Codable {
        /// No whole answer came. macOS's own words say why, in the language Peel ran in: an error made again from its
        /// code alone loses them.
        case noAnswer(String)
        /// The server answered with this HTTP status instead of 200.
        case answered(Int)
        /// The server sent the check on to this address, which isn't https, so the check went no further.
        case sentOnTo(String)
        case tooLarge
        /// What came back can't be read, with the type the server declared for it.
        case unreadable(type: String?)
        /// The App Store answered `version`, older than `found`, the update it offered this build before.
        case olderThanFound(version: String, found: String)
        case unlistedAfterAnUpdate
    }

    /// What an HTTP status other than 200 says, by the classes RFC 9110 gives them.
    public enum StatusMeaning: Sendable, Hashable {
        case nothingThere
        case refused
        case tooManyRequests
        case serverError
        case other

        public init(status: Int) {
            self = switch status {
            case 404, 410: .nothingThere
            case 401, 403, 407: .refused
            case 429: .tooManyRequests
            case 500..<600: .serverError
            default: .other
            }
        }
    }

    public let asked: Asked
    public let cause: Cause

    public init(asked: Asked, cause: Cause) {
        self.asked = asked
        self.cause = cause
    }
}
