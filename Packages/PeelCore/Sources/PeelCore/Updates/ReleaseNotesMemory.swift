public import Foundation

/// What is new in each waiting update, by app, kept so a page can show it with no connection and asked for once per
/// version.
public struct ReleaseNotesMemory: Sendable, Equatable, Codable {
    private struct Entry: Sendable, Equatable, Codable {
        let version: String
        /// Nil once asked for and none were given.
        let notes: ReleaseNotes?
    }

    private var entries: [String: Entry] = [:]

    public init() {}

    /// The notes of the update `identifier`'s app is waiting for, `version`, when they were found.
    public func notes(of identifier: String, version: String) -> ReleaseNotes? {
        entries[identifier].flatMap { $0.version == version ? $0.notes : nil }
    }

    /// Whether the notes of `version` are still to be asked for: nobody asked yet, or no server answered.
    public func asks(_ identifier: String, version: String) -> Bool {
        entries[identifier]?.version != version
    }

    /// Whether the notes of the update `status` names are to be asked for: only an update that waits for the person,
    /// never a version they skipped or an app they told Peel to leave alone.
    public func asks(about status: UpdateStatus?, of app: InstalledApp, with preferences: UpdatePreferences) -> Bool {
        guard preferences.isWaiting(status, for: app), let version = status?.version else { return false }
        return asks(app.bundleIdentifier, version: version)
    }

    public mutating func record(_ lookup: ReleaseNotesLookup, of identifier: String, version: String) {
        switch lookup {
        case .found(let notes): entries[identifier] = Entry(version: version, notes: notes)
        case .notGiven: entries[identifier] = Entry(version: version, notes: nil)
        case .unanswered: break
        }
    }

    /// Forgets the notes of every update that no longer waits. `waiting` maps an app to the version its update brings.
    public mutating func keep(only waiting: [String: String]) {
        entries = entries.filter { waiting[$0.key] == $0.value.version }
    }
}

/// The file the notes are kept in, in Peel's own folder. They can always be asked for again, so a file that cannot be
/// read starts over empty.
public struct ReleaseNotesStore: Sendable {
    public let url: URL

    public init(url: URL = PeelFolder.url.appending(path: "release-notes.json")) {
        self.url = url
    }

    @concurrent
    public func load() async -> ReleaseNotesMemory {
        guard let data = BoundedRead.data(at: url) else { return ReleaseNotesMemory() }
        return (try? JSONDecoder().decode(ReleaseNotesMemory.self, from: data)) ?? ReleaseNotesMemory()
    }

    @concurrent
    public func save(_ memory: ReleaseNotesMemory) async {
        guard let data = try? JSONEncoder().encode(memory) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
