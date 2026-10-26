public import Foundation

/// What Peel knows about one app's updates, kept by bundle identifier so it survives the app being moved.
///
/// Apps are checked on a schedule, so the last answer is saved across launches. Without it, most apps would
/// lose their badge after a relaunch, and drop out of the menu bar count, until their next check.
public struct UpdateMemory: Codable, Equatable, Sendable {
    public let status: UpdateStatus
    public let schedule: UpdateSchedule
    /// When the last answer arrived, as the app's page shows it. A failed check does not change it.
    public let checked: Date?
    /// The version and build the answer was about. An app updated while Peel was closed is a different build,
    /// and the answer about the old build, including when to check again, does not apply to it.
    public let version: String?
    public let buildVersion: String?
    /// The developer's name from the App Store. It is saved because an App Store app's signature is Apple's and
    /// does not name the developer, and the next check may be a week away.
    public let developer: String?
    /// What the app's own feed or the App Store answered, when `status` is Homebrew's answer in its place.
    public let standsInFor: UpdateStatus?
    /// The `UpdateChecker.revision` that gave the answer; nil for one saved before revisions were kept.
    public let revision: Int?
    /// Whether the App Store's answer was that it lists no such app; nil for one saved before this was kept.
    public let isNotListed: Bool?

    public init(
        status: UpdateStatus,
        schedule: UpdateSchedule,
        checked: Date?,
        describing app: InstalledApp,
        developer: String? = nil,
        standsInFor: UpdateStatus? = nil,
        isNotListed: Bool = false
    ) {
        self.status = status
        self.schedule = schedule
        self.checked = checked
        self.developer = developer
        self.standsInFor = standsInFor
        self.isNotListed = isNotListed
        version = app.version
        buildVersion = app.buildVersion
        revision = UpdateChecker.revision
    }

    public func describes(_ app: InstalledApp) -> Bool {
        version == app.version && buildVersion == app.buildVersion
    }

    /// How long past its due date an entry is kept for an app that is not installed, such as one on a disk that
    /// is not connected. Without a limit, the saved list would keep an entry for every app ever seen.
    static let longestAbsence: TimeInterval = 90 * 24 * 60 * 60
}

/// What Peel knows about every app's updates, by bundle identifier, with an entry for each build a copy is at: an app
/// and a beta of it share an identifier, and each keeps its own answer and schedule.
public struct UpdateMemories: Equatable, Sendable {
    private var entries: [String: [UpdateMemory]]

    public init() {
        entries = [:]
    }

    /// One entry per identifier, as Peel saved it before it kept one for each build.
    init(_ earlier: [String: UpdateMemory]) {
        entries = earlier.mapValues { [$0] }
    }

    /// Reads what was saved, in either form, or nil when it can't be read.
    public init?(data: Data) {
        let decoder = JSONDecoder()
        if let builds = try? decoder.decode([String: [UpdateMemory]].self, from: data) {
            entries = builds
        } else if let earlier = try? decoder.decode([String: UpdateMemory].self, from: data) {
            entries = earlier.mapValues { [$0] }
        } else {
            return nil
        }
    }

    public var data: Data? {
        try? JSONEncoder().encode(entries)
    }

    public var isEmpty: Bool {
        entries.isEmpty
    }

    /// The entry about the build `app` is at.
    public func entry(for app: InstalledApp) -> UpdateMemory? {
        app.bundleIdentifier.flatMap { entries[$0] }?.first { $0.describes(app) }
    }

    /// Keeps `entry` for the build `app` is at, in place of the one about that build.
    public mutating func keep(_ entry: UpdateMemory, for app: InstalledApp) {
        guard let identifier = app.bundleIdentifier else { return }
        entries[identifier, default: []].removeAll { $0.describes(app) }
        entries[identifier, default: []].append(entry)
    }

    public mutating func forget(_ app: InstalledApp) {
        guard let identifier = app.bundleIdentifier else { return }
        entries[identifier]?.removeAll { $0.describes(app) }
        if entries[identifier]?.isEmpty == true { entries[identifier] = nil }
    }

    /// The developer the App Store named for any build of the app, the latest kept first.
    public func developer(of identifier: String) -> String? {
        entries[identifier]?.reversed().lazy.compactMap(\.developer).first
    }

    /// The entries that still apply to `apps`. An entry is dropped when no installed copy is the build it describes,
    /// which also makes that copy due at once, when an earlier checker couldn't check the app or gave the answer about
    /// a copy this checker asks nobody about, or when the app is not installed and the entry is more than
    /// `UpdateMemory.longestAbsence` past due.
    public func recalled(for apps: [InstalledApp], now: Date = .now) -> UpdateMemories {
        let installed = InstalledApp.byIdentifier(apps)
        var recalled = UpdateMemories()
        for (identifier, builds) in entries {
            let kept = builds.filter { entry in
                let isEarlier = entry.revision ?? 1 < UpdateChecker.revision
                if entry.status == .unsupported, isEarlier { return false }
                guard let copies = installed[identifier] else {
                    return entry.schedule.due.addingTimeInterval(UpdateMemory.longestAbsence) > now
                }
                let described = copies.filter(entry.describes)
                // An earlier checker may have asked a source this one no longer reads, and answering such a copy
                // again costs no request.
                if isEarlier, described.contains(where: UpdateChecker.asksNobody(about:)) { return false }
                return !described.isEmpty
            }
            if !kept.isEmpty { recalled.entries[identifier] = kept }
        }
        return recalled
    }
}
