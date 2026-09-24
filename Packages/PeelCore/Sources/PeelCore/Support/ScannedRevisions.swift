/// Which revision of a list (such as the exclusions) each page last scanned under, so a page that was not on
/// screen while the list changed scans again when it comes back. It is kept outside the pages because
/// Settings takes the whole pane: while it is open, no tool's view exists to be told.
public struct ScannedRevisions: Sendable {
    private var seen: [String: Int] = [:]

    public init() {}

    /// True when `page` last scanned under another revision, and notes `revision` as its latest. False the
    /// first time a page asks, since its first scan is already running under this revision.
    public mutating func needsRescan(_ page: String, at revision: Int) -> Bool {
        defer { seen[page] = revision }
        guard let last = seen[page] else { return false }
        return last != revision
    }
}
