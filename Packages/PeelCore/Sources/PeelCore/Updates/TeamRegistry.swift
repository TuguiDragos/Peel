public import Foundation
internal import PeelPrivileged

/// Remembers which team signs each app, so the user can be told when a different team, or no team, signs it.
public struct TeamRegistry: Sendable {
    public struct Change: Sendable, Hashable, Codable {
        public let bundleIdentifier: String
        public let previous: String
        public let current: String
    }

    /// Why the registry is not keeping its record, which the person is told, since no warning comes meanwhile.
    public enum Problem: Sendable, Equatable {
        /// The file cannot be read, so nothing is compared or recorded until the person starts it over.
        case unreadable
        /// The file could not be written, so what the last check learned is not kept.
        case unsaved
    }

    public struct Outcome: Sendable, Equatable {
        public let changes: [Change]
        public let problem: Problem?
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
    /// that cannot be read reports nothing, is left as it is, and says so.
    @concurrent
    public func check(_ apps: [InstalledApp], now: Date = .now) async -> Outcome {
        FileLock.whileHeld(beside: url) {
            guard let stored = load() else { return Outcome(changes: [], problem: .unreadable) }
            var entries = stored
            var changes: [Change] = []

            for (identifier, copies) in InstalledApp.byIdentifier(apps).sorted(by: { $0.key < $1.key }) {
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

            let isSaved = entries == stored || save(entries)
            return Outcome(changes: changes, problem: isSaved ? nil : .unsaved)
        }
    }

    /// Records that the user has seen the pending change, so its team counts as known for this app.
    @concurrent
    public func acknowledge(_ bundleIdentifier: String) async -> Problem? {
        FileLock.whileHeld(beside: url) {
            guard var entries = load() else { return .unreadable }
            guard var entry = entries[bundleIdentifier], let pending = entry.pending else { return nil }
            entry.acknowledged = (entry.acknowledged ?? []) + [pending.current]
            entry.pending = nil
            entries[bundleIdentifier] = entry
            return save(entries) ? nil : .unsaved
        }
    }

    /// Keeps a registry that cannot be read beside a new one, which the next check starts recording in. A registry
    /// that reads is left as it is. False when the old file could not be set aside.
    @concurrent
    public func startOver() async -> Bool {
        FileLock.whileHeld(beside: url) {
            load() != nil || DamagedFile.setAside(url) != nil
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

    private func save(_ entries: [String: Entry]) -> Bool {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try encoder.encode(entries)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }
}
