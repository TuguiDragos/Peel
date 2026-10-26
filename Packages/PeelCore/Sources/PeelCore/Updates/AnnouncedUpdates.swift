/// The version of each app's waiting update Peel has told the person of, by the app's `reference`, so each update is
/// told of once, whoever found it: a round of checks or a reading of Homebrew.
public struct AnnouncedUpdates: Equatable, Sendable {
    public private(set) var versions: [String: String]

    public init(versions: [String: String] = [:]) {
        self.versions = versions
    }

    /// The apps in `waiting` whose update `version` hasn't been told of, which then count as told. None while a round
    /// of checks runs, so an update is told of once every round that may find it has ended.
    public mutating func takeNew(
        _ waiting: [InstalledApp], version: (InstalledApp) -> String?, whileChecking isChecking: Bool
    ) -> [InstalledApp] {
        guard !isChecking else { return [] }
        let new = waiting.compactMap { app in
            version(app).flatMap { versions[app.reference] == $0 ? nil : (app, $0) }
        }
        for (app, version) in new {
            versions[app.reference] = version
        }
        return new.map(\.0)
    }
}
