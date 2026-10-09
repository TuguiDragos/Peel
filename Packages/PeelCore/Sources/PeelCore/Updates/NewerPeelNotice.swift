/// When Peel tells with a notification that a newer version of itself is out: once for each version.
public enum NewerPeelNotice {
    public struct Answer: Sendable, Hashable {
        public let tell: Bool
        /// The version told last, which the next check is given.
        public let told: String?
    }

    public static func check(newer: String?, told: String?) -> Answer {
        guard let newer, newer != told else { return Answer(tell: false, told: told) }
        return Answer(tell: true, told: newer)
    }
}
