import Foundation

struct AppOwnership: Sendable {
    private let profiles: [LeftoverMatcher.Profile]
    private let goneApps: [String]
    private let isRegisteredApp: @Sendable (String) -> Bool

    /// `goneApps` are the identifiers of the apps Peel saw installed that are gone.
    init(
        installedApps: [InstalledApp],
        goneApps: [String] = [],
        isRegisteredApp: @escaping @Sendable (String) -> Bool
    ) {
        profiles = installedApps.map(LeftoverMatcher.Profile.init)
        self.goneApps = goneApps.map { $0.lowercased() }
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
        // An identifier that was a gone app's own is that app's: a shorter prefix of it or its maker claims nothing.
        let gone = goneApp(owning: identifier)
        let claims = { (evidence: LeftoverMatcher.Evidence) in
            guard let gone else { return true }
            switch evidence.reason {
            case .bundleIdentifierPrefix: return evidence.specificity > gone.count + 1
            case .teamIdentifier, .vendorPrefix, .namePrefix: return false
            default: return true
            }
        }
        if profiles.contains(where: { profile in
            candidates.contains { profile.evidence(for: $0).map(claims) ?? false }
        }) {
            return true
        }
        // macOS knows an app by its bundle identifier, never by a container's name with a team or `group.` in front.
        // A Safari web app's identifier is Safari's web app template followed by its own UUID, and that template, an
        // app Launch Services knows, is no owner of the web app's files.
        var components = OrphanScanner.groupingKey(for: identifier).split(separator: ".")
        let shortest = SafariWebApp.isIdentifier(identifier)
            ? components.count : max(3, gone.map { $0.split(separator: ".").count } ?? 3)
        while components.count >= shortest {
            if isRegisteredApp(components.joined(separator: ".")) {
                return true
            }
            components.removeLast()
        }
        return false
    }

    /// The longest identifier of a gone app that `identifier` is, or begins with before a dot.
    private func goneApp(owning identifier: String) -> String? {
        let key = OrphanScanner.groupingKey(for: identifier).lowercased()
        return goneApps.filter { key == $0 || key.hasPrefix($0 + ".") }.max { $0.count < $1.count }
    }

    static func launchServicesKnowsApp(withBundleIdentifier identifier: String) -> Bool {
        AppInspector.applicationURL(forBundleIdentifier: identifier) != nil
    }
}
