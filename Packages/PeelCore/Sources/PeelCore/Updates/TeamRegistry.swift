public import Foundation

/// Remembers which team signs each app, so the user can be told when a different team, or no team, signs it.
public struct TeamRegistry: Sendable {
    public struct Change: Sendable, Hashable, Codable {
        public let bundleIdentifier: String
        public let previous: String
        public let current: String
    }

    struct Entry: Codable, Sendable, Equatable {
        /// The first team seen signing the app.
        var team: String
        /// Other teams the user has been told about and acknowledged, with "" for no team. Keeping all of them
        /// stops two copies of one app, signed by two teams, from each being reported as a change from the other.
        var acknowledged: [String]?
        /// A change of signer that the user has not acknowledged yet. It is saved because the user may not open
        /// the page that shows it in the session that found it.
        var pending: Change?
        /// When the app was first seen with no team. A bundle in the middle of an update also has no team for a
        /// moment, so a missing team is reported only after `settlingTime`.
        var unsignedSince: Date?

        var known: Set<String> { Set([team] + (acknowledged ?? [])) }
    }

    /// How long an app has to stay without a team before that is reported.
    static let settlingTime: TimeInterval = 10 * 60

    public let url: URL

    public init(url: URL = TeamRegistry.defaultURL) {
        self.url = url
    }

    public static var defaultURL: URL {
        PeelFolder.url.appending(path: "teams.json")
    }

    /// Records the team of every app, and returns a change for each app signed by a team not known for it. A
    /// change is returned on every call until the user acknowledges it, or a known team signs the app again.
    /// `current` is empty when no team signs the app, which is what a tampered copy looks like. A registry file
    /// that cannot be read reports nothing and is left as it is.
    @concurrent
    public func check(_ apps: [InstalledApp], now: Date = .now) async -> [Change] {
        FileLock.whileHeld(beside: url) {
            guard let stored = load() else { return [] }
            var entries = stored
            var changes: [Change] = []

            for (identifier, copies) in Dictionary(grouping: apps, by: \.bundleIdentifier).sorted(by: { $0.key < $1.key }) {
                let teams = Set(copies.compactMap(\.teamIdentifier).filter { !$0.isEmpty })
                guard var entry = entries[identifier] else {
                    if let first = teams.sorted().first { entries[identifier] = Entry(team: first) }
                    continue
                }
                entry.unsignedSince = teams.isEmpty ? entry.unsignedSince ?? now : nil
                let hasSettled = entry.unsignedSince.map { now.timeIntervalSince($0) > Self.settlingTime } ?? false
                let unknown = teams.isEmpty ? (hasSettled ? [""] : []) : teams.subtracting(entry.known).sorted()
                if let current = unknown.first(where: { !entry.known.contains($0) }) {
                    if entry.pending?.current != current {
                        entry.pending = Change(bundleIdentifier: identifier, previous: entry.team, current: current)
                    }
                } else {
                    entry.pending = nil
                }
                entries[identifier] = entry
                if let pending = entry.pending { changes.append(pending) }
            }

            if entries != stored { save(entries) }
            return changes
        }
    }

    /// Records that the user has seen the pending change, so its team counts as known for this app.
    @concurrent
    public func acknowledge(_ bundleIdentifier: String) async {
        FileLock.whileHeld(beside: url) {
            guard var entries = load(), var entry = entries[bundleIdentifier], let pending = entry.pending else { return }
            entry.acknowledged = (entry.acknowledged ?? []) + [pending.current]
            entry.pending = nil
            entries[bundleIdentifier] = entry
            save(entries)
        }
    }

    /// Returns nil for a file that cannot be read, reached or decoded. Rebuilt from the apps as they are, the
    /// registry would silently accept any change of team made since it was last read.
    private func load() -> [String: Entry]? {
        guard !url.isMissing else { return [:] }
        guard let data = BoundedRead.data(at: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode([String: Entry].self, from: data)
    }

    private func save(_ entries: [String: Entry]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(entries) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
