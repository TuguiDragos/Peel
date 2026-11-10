import Foundation

struct AppOwnership: Sendable {
    private let profiles: [LeftoverMatcher.Profile]
    private let claimants: Claimants
    /// Every run of whole words in the installed apps' names (`LeftoverMatcher.Profile.wordRuns`).
    private let wordRuns: Set<String>
    private let goneApps: Set<String>
    /// The makers of the gone apps (`Identifier.vendor(of:)`).
    private let goneMakers: Set<String>
    private let goneFromTheAppStore: Set<String>
    private let isRegisteredApp: @Sendable (String) -> Bool
    /// The identifiers the installed apps and the gone ones declared, lowercased.
    private let declared: Set<String>
    /// The folders the Developer page's table names as a tool's.
    private let toolsFolders: DeveloperCaches.FoldersLeftToDeveloper?

    /// `goneApps` are the identifiers of the apps Peel saw installed that are gone, and `goneFromTheAppStore` those
    /// of them the App Store signed under their identifier.
    init(
        installedApps: [InstalledApp],
        goneApps: [String] = [],
        goneFromTheAppStore: [String] = [],
        toolsFolders: DeveloperCaches.FoldersLeftToDeveloper? = nil,
        isRegisteredApp: @escaping @Sendable (String) -> Bool
    ) {
        profiles = installedApps.map(LeftoverMatcher.Profile.init)
        claimants = Claimants(profiles)
        wordRuns = Set(profiles.flatMap(\.wordRuns))
        let gone = goneApps.map { $0.lowercased() }
        self.goneApps = Set(gone)
        goneMakers = Set(gone.compactMap(Identifier.vendor(of:)))
        self.goneFromTheAppStore = Set(goneFromTheAppStore.map { $0.lowercased() })
        self.toolsFolders = toolsFolders
        self.isRegisteredApp = isRegisteredApp
        declared = Set(installedApps.compactMap { $0.bundleIdentifier?.lowercased() } + gone)
    }

    /// Whether `name` is an identifier an app declared, or one with three parts or more followed by a dot, as
    /// `AppMemory.app(for:in:)` reads it: then it names that app's files whatever its shape.
    func isDeclared(_ name: String) -> Bool {
        var components = name.lowercased().split(separator: ".", omittingEmptySubsequences: false)
        if declared.contains(components.joined(separator: ".")) { return true }
        while components.count > 3 {
            components.removeLast()
            if declared.contains(components.joined(separator: ".")) { return true }
        }
        return false
    }

    /// Whether `url`, listed as `identifier`, is a folder the Developer page knows as a tool's, with no app Peel saw go
    /// behind it: a tool such as Carthage has no app, and its folder only looks like one's.
    func isAToolsFolder(_ url: URL, identifier: String) -> Bool {
        guard let toolsFolders, goneApp(owning: identifier) == nil else { return false }
        return toolsFolders.isOneOf(url)
    }

    func isAGoneApp(_ identifier: String) -> Bool {
        goneApps.contains(identifier.lowercased())
    }

    /// Whether `identifier` is a gone app's that the App Store signed under it, which names that app's files alone.
    func isAGoneAppStoreApp(_ identifier: String) -> Bool {
        goneFromTheAppStore.contains(identifier.lowercased())
    }

    /// Returns whether an installed app has any claim on the item, even a weak one, or macOS knows an app by the
    /// item's identifier, by a prefix of it with at least three components, or by the identifier of the gone app it
    /// belongs to, whatever its shape. The apps are asked about the identifier as well as the name, since a plug-in is
    /// named for what it does and a container can be a UUID.
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
        if candidates.contains(where: { candidate in
            claimants.of(candidate).contains { profiles[$0].claim(for: candidate).map(claims) ?? false }
        }) {
            return true
        }
        // macOS knows an app by its bundle identifier, never by a container's name with a team or `group.` in front.
        // A Safari web app's identifier is Safari's web app template followed by its own UUID, and that template, an
        // app Launch Services knows, is no owner of the web app's files.
        var components = OrphanScanner.groupingKey(for: identifier).split(separator: ".")
        let shortest = SafariWebApp.isIdentifier(identifier)
            ? components.count : gone.map { $0.split(separator: ".").count } ?? 3
        while components.count >= shortest {
            if isRegisteredApp(components.joined(separator: ".")) {
                return true
            }
            components.removeLast()
        }
        return false
    }

    /// Whether an installed app's name holds the item's name as whole words, as Epic Games Launcher holds Epic: what
    /// only its name ties to a gone app may be that app's.
    func anInstalledAppsNameHolds(fileName: String, kind: SearchLocation.Kind) -> Bool {
        let candidate = LeftoverMatcher.Candidate(LeftoverMatcher.key(from: fileName, kind: kind))
        return candidate.isLongEnoughToShare && wordRuns.contains(candidate.normalized)
    }

    /// Whether `identifier` is a gone app's, extends one after a dot, or is of a gone app's maker: a plug-in can come
    /// with an app, and with no app at all from an installer.
    func cameWithAnAppThatLeft(_ identifier: String) -> Bool {
        let plugIn = identifier.lowercased()
        if goneApp(beginning: plugIn) != nil { return true }
        return Identifier.vendor(of: plugIn).map(goneMakers.contains) ?? false
    }

    /// The longest identifier of a gone app that `identifier` is, or begins with before a dot.
    private func goneApp(owning identifier: String) -> String? {
        goneApp(beginning: OrphanScanner.groupingKey(for: identifier).lowercased())
    }

    /// The longest identifier of a gone app that `key`, lowercased, is or begins with before a dot.
    private func goneApp(beginning key: String) -> String? {
        if goneApps.contains(key) { return key }
        return key.indices.filter { key[$0] == "." }.map { String(key[..<$0]) }.last(where: goneApps.contains)
    }

    /// The profiles that may claim a name, found by what each claims by: an item asks only those, and each still
    /// answers by its own rule (`LeftoverMatcher.Profile.claim(for:)`).
    private struct Claimants {
        private var exact: [String: [Int]] = [:]
        /// A prefix of an identifier and a team, each ending in its separator.
        private var beginnings: [String: [Int]] = [:]
        private var makers: [String: [Int]] = [:]
        private var names: [String: [Int]] = [:]
        /// The first letter of each name, for a key that begins with the name's words.
        private var firstLetters: [Character: [Int]] = [:]

        init(_ profiles: [LeftoverMatcher.Profile]) {
            for (index, profile) in profiles.enumerated() {
                for key in [profile.identifier].compactMap(\.self) + profile.embeddedIdentifiers.map(\.value)
                    + profile.applicationGroups {
                    exact[key, default: []].append(index)
                }
                for beginning in profile.prefixes + [profile.teamPrefix].compactMap(\.self) {
                    beginnings[beginning, default: []].append(index)
                }
                if let maker = profile.vendorPrefix { makers[maker, default: []].append(index) }
                for name in profile.normalizedNames.union(profile.channelNames) {
                    names[name, default: []].append(index)
                }
                for letter in Set(profile.names.compactMap { Naming.normalized($0).first }) {
                    firstLetters[letter, default: []].append(index)
                }
            }
        }

        /// The profiles that may claim `candidate`, in no particular order.
        func of(_ candidate: LeftoverMatcher.Candidate) -> Set<Int> {
            let key = candidate.key
            var found = Set(exact[key] ?? [])
            for end in key.indices where [".", "-", "_"].contains(key[end]) {
                found.formUnion(beginnings[String(key[...end])] ?? [])
            }
            let withoutCatalyst = Identifier.withoutCatalystPrefix(key) + "."
            for end in withoutCatalyst.indices where withoutCatalyst[end] == "." {
                found.formUnion(makers[String(withoutCatalyst[...end])] ?? [])
            }
            for name in [candidate.normalized, candidate.withoutVersion].compactMap(\.self) {
                found.formUnion(names[name] ?? [])
            }
            let words = key.split(whereSeparator: Naming.separators.contains).lazy.map { Naming.normalized(String($0)) }
            if let letter = words.first(where: { !$0.isEmpty })?.first {
                found.formUnion(firstLetters[letter] ?? [])
            }
            return found
        }
    }

    static func launchServicesKnowsApp(withBundleIdentifier identifier: String) -> Bool {
        AppInspector.applicationURL(forBundleIdentifier: identifier) != nil
    }
}
