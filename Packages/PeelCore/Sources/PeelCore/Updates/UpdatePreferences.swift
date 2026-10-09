public import Foundation
internal import PeelPrivileged

/// What the user told Peel about updates. The app keeps these in its own preferences and the command line
/// reads the same ones, so the two can't disagree about what is waiting.
public struct UpdatePreferences: Sendable, Hashable {
    public enum Key {
        public static let source = "updateSource"
        public static let ignoredApps = "ignoredUpdateApps"
        public static let skippedVersions = "skippedUpdateVersions"
    }

    public var source: UpdateSource
    /// The apps the user told Peel never to check, by `InstalledApp.reference`.
    public var ignoredApps: Set<String>
    /// The version the user chose to skip for each app, by `InstalledApp.reference`.
    public var skippedVersions: [String: String]

    public init(
        source: UpdateSource = .automatic,
        ignoredApps: Set<String> = [],
        skippedVersions: [String: String] = [:]
    ) {
        self.source = source
        self.ignoredApps = ignoredApps
        self.skippedVersions = skippedVersions
    }

    public func isIgnored(_ app: InstalledApp) -> Bool {
        ignoredApps.contains(app.reference)
    }

    /// Whether `status` is an update worth showing: the app is not ignored and that version was not skipped.
    /// The app list, the menu bar count, the notification, and the command line all ask this, so they agree.
    public func isWaiting(_ status: UpdateStatus?, for app: InstalledApp) -> Bool {
        guard case .updateAvailable(let version, _, _) = status else { return false }
        return !isIgnored(app) && skippedVersions[app.reference] != version
    }

    /// The answer an app's page shows. An update the user muted, by skipping that version or by telling Peel never
    /// to check the app, is not announced again; any other answer is shown as it came.
    public func shownStatus(_ status: UpdateStatus?, for app: InstalledApp) -> UpdateStatus? {
        guard case .updateAvailable = status else { return status }
        return isWaiting(status, for: app) ? status : nil
    }

    public static func read(from defaults: UserDefaults) -> UpdatePreferences {
        UpdatePreferences(
            source: UpdateSource(rawValue: defaults.string(forKey: Key.source) ?? "") ?? .automatic,
            ignoredApps: Set(defaults.stringArray(forKey: Key.ignoredApps) ?? []),
            skippedVersions: defaults.dictionary(forKey: Key.skippedVersions) as? [String: String] ?? [:]
        )
    }

    /// Reads the app's update settings from any process. The command line tool has a defaults domain of its
    /// own, so it reads the app's domain as a suite. Inside the app that domain is the standard one, because
    /// passing the app's own identifier as a suite name is an error (`NSUserDefaults.h`).
    public static func asTheAppSeesThem() -> UpdatePreferences {
        guard Bundle.main.bundleIdentifier != HelperIdentity.appIdentifier else { return read(from: .standard) }
        guard let defaults = UserDefaults(suiteName: HelperIdentity.appIdentifier) else { return UpdatePreferences() }
        return read(from: defaults)
    }
}
