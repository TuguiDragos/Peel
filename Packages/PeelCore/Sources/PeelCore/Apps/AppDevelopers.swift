import Foundation

/// Who makes each app, as the Applications list names them. The signature names a Developer ID app or one of
/// Apple's. An App Store app, which Apple signs again, takes the name of another installed app of its team, or else
/// the name the App Store gave at the last update check.
public struct AppDevelopers: Sendable {
    private let byTeam: [String: String]

    public init(_ apps: [InstalledApp]) {
        byTeam = Dictionary(
            apps.compactMap { app in app.developer.flatMap { name in app.teamIdentifier.map { ($0, name) } } },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// `remembered` is what the App Store answered for the app.
    public func developer(of app: InstalledApp, remembered: String?) -> String? {
        app.developer ?? app.teamIdentifier.flatMap { byTeam[$0] } ?? remembered
    }

    /// The developers with two or more apps among `names`, one per app, for the list's filter, and `chosen` even when
    /// none of its apps remain, since it is what empties the list. A developer with one app is left out to keep the
    /// menu short: search finds that app by its developer anyway.
    public static func offered(_ names: [String], chosen: String?) -> [String] {
        let counts = Dictionary(names.map { ($0, 1) }, uniquingKeysWith: +)
        return Set(counts.filter { $0.value > 1 }.map(\.key) + [chosen].compactMap(\.self))
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}
