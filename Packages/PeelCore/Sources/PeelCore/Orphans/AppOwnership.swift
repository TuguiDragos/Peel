import Foundation

struct AppOwnership: Sendable {
    private let profiles: [LeftoverMatcher.Profile]
    private let isRegisteredApp: @Sendable (String) -> Bool

    init(installedApps: [InstalledApp], isRegisteredApp: @escaping @Sendable (String) -> Bool) {
        profiles = installedApps.map(LeftoverMatcher.Profile.init)
        self.isRegisteredApp = isRegisteredApp
    }

    /// Returns whether an installed app has any claim on the item, even a weak one, or macOS knows an app by the
    /// item's identifier or by a prefix of it with at least three components. The apps are asked about the
    /// identifier as well as the name, since a plug-in is named for what it does and a container can be a UUID.
    func isClaimed(fileName: String, kind: SearchLocation.Kind, identifier: String) -> Bool {
        var candidates = [LeftoverMatcher.Candidate(LeftoverMatcher.key(from: fileName, kind: kind))]
        if candidates[0].key != identifier.lowercased() {
            candidates.append(LeftoverMatcher.Candidate(identifier))
        }
        if profiles.contains(where: { profile in candidates.contains { profile.evidence(for: $0) != nil } }) {
            return true
        }
        // macOS knows an app by its bundle identifier, never by a container's name with a team or `group.` in front.
        var components = OrphanScanner.groupingKey(for: identifier).split(separator: ".")
        while components.count >= 3 {
            if isRegisteredApp(components.joined(separator: ".")) {
                return true
            }
            components.removeLast()
        }
        return false
    }

    static func launchServicesKnowsApp(withBundleIdentifier identifier: String) -> Bool {
        AppInspector.applicationURL(forBundleIdentifier: identifier) != nil
    }
}
