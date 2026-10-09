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

    public init(
        status: UpdateStatus,
        schedule: UpdateSchedule,
        checked: Date?,
        describing app: InstalledApp,
        developer: String? = nil
    ) {
        self.status = status
        self.schedule = schedule
        self.checked = checked
        self.developer = developer
        version = app.version
        buildVersion = app.buildVersion
    }

    public func describes(_ app: InstalledApp) -> Bool {
        version == app.version && buildVersion == app.buildVersion
    }

    /// How long past its due date an entry is kept for an app that is not installed, such as one on a disk that
    /// is not connected. Without a limit, the saved list would keep an entry for every app ever seen.
    static let longestAbsence: TimeInterval = 90 * 24 * 60 * 60

    /// Returns the entries that still apply to `apps`. An entry is dropped when no installed copy is the build it
    /// describes, which also makes that app due at once, or when the app is not installed and the entry is more
    /// than `longestAbsence` past due. With two copies at two builds, the entry describes one of them and stays.
    public static func recalled(
        from memory: [String: UpdateMemory],
        for apps: [InstalledApp],
        now: Date = .now
    ) -> [String: UpdateMemory] {
        let installed = InstalledApp.byIdentifier(apps)
        return memory.filter { identifier, entry in
            guard let copies = installed[identifier] else {
                return entry.schedule.due.addingTimeInterval(longestAbsence) > now
            }
            return copies.contains(where: entry.describes)
        }
    }
}
