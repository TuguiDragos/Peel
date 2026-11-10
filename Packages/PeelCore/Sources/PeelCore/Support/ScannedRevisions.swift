/// Which revision of a list (such as the exclusions) each page last scanned under, so a page that was not on
/// screen while the list changed scans again when it comes back. It is kept outside the pages because
/// Settings takes the whole pane: while it is open, no tool's view exists to be told.
public struct ScannedRevisions: Sendable {
    private var seen: [String: Int] = [:]

    public init() {}

    /// True when `page` last scanned under another revision. The first time a page asks, the revision is noted and the
    /// answer is false, since its first scan is already running under it.
    public mutating func needsRescan(_ page: String, at revision: Int) -> Bool {
        guard let last = seen[page] else {
            seen[page] = revision
            return false
        }
        return last != revision
    }

    /// Notes that a scan of `page` under `revision` landed. Until then the page still owes one, so a rescan dropped
    /// because the page went away runs again when it comes back.
    public mutating func scanned(_ page: String, at revision: Int) {
        seen[page] = revision
    }
}
