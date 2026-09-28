import Foundation
internal import PeelPrivileged

struct LeftoverMatcher: Sendable {
    /// Where macOS says the app with an identifier is, which can be outside the Applications folders.
    typealias RegisteredApp = @Sendable (String) -> URL?

    private let target: Profile
    private let others: [Profile]
    private let bundlePath: String
    private let registeredApp: RegisteredApp

    init(
        app: InstalledApp,
        installedApps: [InstalledApp],
        registeredApp: @escaping RegisteredApp = AppInspector.applicationURL(forBundleIdentifier:)
    ) {
        target = Profile(app)
        // By path, not by URL: two URLs for the same bundle can differ by a trailing slash.
        bundlePath = PathPattern.comparablePath(of: app.url)
        let path = bundlePath
        let real = PathPattern.comparablePath(of: PathPattern.canonical(app.url))
        others = installedApps.filter { other in
            guard PathPattern.comparablePath(of: other.url) != path else { return false }
            // Spelled in another case or reached through a link, it is still this app. As its own rival, it would
            // share every file with itself. Only a bundle with the same identifier is worth checking on disk.
            guard other.bundleIdentifier == app.bundleIdentifier else { return true }
            return PathPattern.comparablePath(of: PathPattern.canonical(other.url)) != real
        }
        .map(Profile.init)
        self.registeredApp = registeredApp
    }

    /// This app's claim on the item called `fileName` in a location of `kind`, found at `url` when the caller knows it.
    func match(fileName: String, kind: SearchLocation.Kind, at url: URL? = nil) -> LeftoverMatch? {
        let key = Self.key(from: fileName, kind: kind)
        // A hidden file outside the home folder is the system's own: `.GlobalPreferences.plist` is the global domain.
        guard !key.hasPrefix(".") else { return nil }
        let candidate = Candidate(key)
        guard let evidence = target.evidence(for: candidate) else { return nil }

        var sharedWith: Set<String> = []
        var otherCopies: [URL] = []
        func share(with other: Profile) {
            if other.identifier == target.identifier {
                otherCopies.append(other.url)
            } else {
                sharedWith.insert(other.bundleIdentifier)
            }
        }
        // An app inside the item goes with it, such as an agent or an update an app keeps in its own folder.
        let item = url.map(PathPattern.comparablePath)
        func goesWithTheItem(_ other: Profile) -> Bool {
            guard let item, other.path.hasPrefix(item) else { return false }
            return PathComponents.isPath(other.path, atOrInside: item)
        }
        for other in others where !goesWithTheItem(other) {
            guard let rival = other.evidence(for: candidate) else {
                // Siblings from the same maker, like Firefox Nightly beside Firefox, use the same files.
                if target.isSibling(of: other), other.sharesName(with: candidate) {
                    share(with: other)
                }
                continue
            }
            // A likely claim by name against one by identifier: neither wins, whatever their ranks, and the item
            // is shared. Otherwise the stronger claim wins, as with Chrome and Chrome Canary, and equal ones share.
            if rival.family != evidence.family, rival.confidence >= .likely, evidence.confidence >= .likely {
                share(with: other)
            } else if rival.rank > evidence.rank {
                return nil
            } else if rival.rank == evidence.rank {
                share(with: other)
            }
        }
        if evidence.reason == .bundleIdentifierPrefix {
            sharedWith.formUnion(appsElsewhere(answeringTo: key))
        }
        return LeftoverMatch(
            reason: evidence.reason,
            confidence: evidence.confidence,
            sharedWith: sharedWith.sorted(),
            otherCopies: otherCopies,
            isAWord: evidence.isAWord
        )
    }

    /// Identifiers of apps macOS knows, wherever they are installed, that `key` may belong to. The list of
    /// installed apps covers only the two Applications folders, and Chrome Canary on another disk must still
    /// count as a rival for `com.google.Chrome.canary`. macOS is asked about each prefix of `key` with more
    /// components than the app's identifier. An app found inside this bundle is the app's own helper, not a rival.
    private func appsElsewhere(answeringTo key: String) -> [String] {
        let parts = key.split(separator: ".", omittingEmptySubsequences: false)
        let own = target.bundleIdentifier.split(separator: ".").count
        guard parts.count > own else { return [] }
        return ((own + 1)...parts.count).compactMap { length in
            let identifier = parts.prefix(length).joined(separator: ".")
            guard let url = registeredApp(identifier) else { return nil }
            let path = PathPattern.comparablePath(of: url)
            return PathComponents.isPath(path, atOrInside: bundlePath) ? nil : identifier
        }
    }

    /// The other installed apps with any claim on `fileName`, by bundle identifier, and the other copies of this app
    /// with one. A path a Homebrew cask names is checked this way too, so one shared with another app or another
    /// copy is never selected for this app.
    func othersClaiming(fileName: String, kind: SearchLocation.Kind) -> (apps: [String], copies: [URL]) {
        let candidate = Candidate(Self.key(from: fileName, kind: kind))
        let claiming = others.filter { $0.evidence(for: candidate) != nil }
        return (
            claiming.filter { $0.identifier != target.identifier }.map(\.bundleIdentifier).sorted(),
            claiming.filter { $0.identifier == target.identifier }.map(\.url)
        )
    }

    static func key(from fileName: String, kind: SearchLocation.Kind) -> String {
        switch kind {
        case .preferences, .launchAgents, .launchDaemons:
            fileName.removingSuffix(".plist")
        case .preferencesByHost:
            removingHostIdentifier(from: fileName.removingSuffix(".plist"))
        case .savedApplicationState:
            fileName.removingSuffix(".savedState")
        case .recentDocuments:
            fileName.removingSuffix(".sfl3").removingSuffix(".sfl2").removingSuffix(".sfl")
        case .cookies, .httpStorages:
            fileName.removingSuffix(".binarycookies")
        case .logs:
            fileName.removingSuffix(".log")
        case .plugIns:
            withoutPlugInExtension(fileName)
        case .frameworks:
            fileName.removingSuffix(".framework")
        case .hiddenHomeFiles:
            fileName.hasPrefix(".") ? String(fileName.dropFirst()) : fileName
        default:
            fileName
        }
    }

    /// The extensions that say a plug-in's kind, listed one by one rather than cutting the name at its last dot:
    /// an unknown kind is missed, never given to the wrong app.
    private static let plugInExtensions = [
        ".component", ".vst3", ".vst", ".clap", ".driver", ".plugin", ".webplugin", ".bundle", ".mailbundle",
        ".prefPane", ".qlgenerator", ".saver", ".qtz", ".mdimporter", ".service", ".workflow", ".colorPicker",
        ".menu", ".inputmethod", ".app", ".aaxplugin", ".dictionary", ".action", ".kext", ".fs",
    ]

    static func withoutPlugInExtension(_ fileName: String) -> String {
        for suffix in plugInExtensions {
            let trimmed = fileName.removingSuffix(suffix)
            if trimmed != fileName { return trimmed }
        }
        return fileName
    }

    /// "com.example.app.0A1B2C3D-…" → "com.example.app"
    private static func removingHostIdentifier(from name: String) -> String {
        guard let dot = name.lastIndex(of: ".") else { return name }
        let suffix = name[name.index(after: dot)...]
        let isHostIdentifier = suffix.count >= 12 && suffix.allSatisfy { $0.isHexDigit || $0 == "-" }
        return isHostIdentifier ? String(name[..<dot]) : name
    }
}

extension LeftoverMatcher {
    struct Candidate {
        let key: String
        let normalized: String
        let isApple: Bool

        init(_ key: String) {
            self.key = key.lowercased()
            normalized = Naming.normalized(key)
            isApple = ProtectedData.isApplesName(key)
        }
    }

    struct Evidence {
        enum Family {
            case identifier
            case name
            case maker
        }

        let reason: MatchReason
        let confidence: MatchConfidence
        let rank: Int
        let family: Family
        /// An identifier that is only a word, such as `notes`, which a folder of anybody's could be called.
        let isAWord: Bool

        init(_ reason: MatchReason, _ confidence: MatchConfidence, specificity: Int) {
            self.reason = reason
            self.confidence = confidence
            isAWord = false
            rank = Self.tier(of: reason) * 10_000 + specificity
            family = switch reason {
            case .bundleIdentifier, .embeddedBundleIdentifier, .applicationGroup, .bundleIdentifierPrefix, .launchdJob, .linksToTheApp, .installerReceipt: .identifier
            case .name, .namePrefix, .homebrewCask: .name
            case .teamIdentifier, .vendorPrefix: .maker
            }
        }

        /// Evidence from an identifier that does not have the shape of one, such as a single word. It proves no
        /// more than a name, so it keeps its reason but ranks and shares like a name.
        init(unproven reason: MatchReason, for candidate: Candidate) {
            self.reason = reason
            confidence = .likely
            isAWord = !candidate.key.contains(".")
            rank = Self.tier(of: .name) * 10_000 + candidate.normalized.count
            family = .name
        }

        private static func tier(of reason: MatchReason) -> Int {
            switch reason {
            // A job's program or a link's target lies inside the app's bundle, which no other app can share.
            case .launchdJob, .linksToTheApp: 8
            case .bundleIdentifier, .installerReceipt: 7
            case .embeddedBundleIdentifier, .applicationGroup: 6
            case .bundleIdentifierPrefix: 5
            case .name: 4
            case .teamIdentifier: 3
            case .vendorPrefix: 2
            case .namePrefix: 1
            case .homebrewCask: 0
            }
        }
    }

    struct EmbeddedIdentifier {
        let value: String
        let sharesVendor: Bool
    }

    struct Profile {
        /// The team Apple signs some of its own apps with, Xcode among them.
        static let appleTeam = "59gab85efg."

        let url: URL
        /// Where the bundle is, spelled to be compared (`PathPattern.comparablePath`).
        let path: String
        let bundleIdentifier: String
        let identifier: String
        let embeddedIdentifiers: [EmbeddedIdentifier]
        let prefixes: [String]
        let applicationGroups: Set<String>
        let teamPrefix: String?
        let vendorPrefix: String?
        let names: [String]
        let normalizedNames: Set<String>
        let isApplesOwn: Bool

        init(_ app: InstalledApp) {
            url = app.url
            path = PathPattern.comparablePath(of: app.url)
            bundleIdentifier = app.bundleIdentifier
            identifier = app.bundleIdentifier.lowercased()
            let vendor = Identifier.vendor(of: identifier)
            embeddedIdentifiers = app.embeddedBundleIdentifiers.map {
                EmbeddedIdentifier(value: $0.lowercased(), sharesVendor: vendor != nil && Identifier.vendor(of: $0) == vendor)
            }
            prefixes = ([identifier] + embeddedIdentifiers.map(\.value))
                .filter { Identifier.componentCount(of: $0) >= 3 }
                .map { $0 + "." }
            applicationGroups = Set(app.applicationGroups.map { $0.lowercased() })
            teamPrefix = app.teamIdentifier.map { $0.lowercased() + "." }
            vendorPrefix = vendor.map { $0 + "." }
            names = app.matchingNames.filter(Naming.isSignificant).map { $0.lowercased() }
            normalizedNames = Set(names.map(Naming.normalized))
            isApplesOwn = app.isSystemProtected || teamPrefix == Self.appleTeam
        }

        func isSibling(of other: Profile) -> Bool {
            if let vendorPrefix, vendorPrefix == other.vendorPrefix { return true }
            if let teamPrefix, teamPrefix == other.teamPrefix { return true }
            return false
        }

        /// True when one of this app's names begins with the candidate, or the candidate begins with it, like
        /// "Firefox Nightly" and "Firefox".
        func sharesName(with candidate: Candidate) -> Bool {
            guard candidate.normalized.count >= 4 else { return false }
            return normalizedNames.contains { $0.hasPrefix(candidate.normalized) || candidate.normalized.hasPrefix($0) }
        }

        func evidence(for candidate: Candidate) -> Evidence? {
            let key = candidate.key
            // Everything an app says about itself (its identifier, what it embeds, the groups it claims)
            // comes from a bundle anyone can write. Only an app Apple signed may answer for Apple's files.
            guard !candidate.isApple || isApplesOwn else { return nil }

            if key == identifier {
                guard Identifier.isValid(key) else { return Evidence(unproven: .bundleIdentifier, for: candidate) }
                return Evidence(.bundleIdentifier, .certain, specificity: key.count)
            }
            if let embedded = embeddedIdentifiers.first(where: { $0.value == key }) {
                guard Identifier.isValid(key) else { return Evidence(unproven: .embeddedBundleIdentifier, for: candidate) }
                return Evidence(.embeddedBundleIdentifier, embedded.sharesVendor ? .certain : .likely, specificity: key.count)
            }
            if applicationGroups.contains(key) {
                guard Identifier.isGroup(key) else { return Evidence(unproven: .applicationGroup, for: candidate) }
                return Evidence(.applicationGroup, .certain, specificity: key.count)
            }
            guard !candidate.isApple else { return nil }

            if let prefix = prefixes.filter({ key.hasPrefix($0) }).max(by: { $0.count < $1.count }) {
                return Evidence(.bundleIdentifierPrefix, .likely, specificity: prefix.count)
            }
            if normalizedNames.contains(candidate.normalized) {
                return Evidence(.name, .likely, specificity: candidate.normalized.count)
            }
            if let teamPrefix, key.hasPrefix(teamPrefix) {
                return Evidence(.teamIdentifier, .possible, specificity: teamPrefix.count)
            }
            if let vendorPrefix, key.hasPrefix(vendorPrefix) {
                return Evidence(.vendorPrefix, .possible, specificity: vendorPrefix.count)
            }
            if let name = names.filter({ Naming.hasNamePrefix(key, name: $0) }).max(by: { $0.count < $1.count }) {
                return Evidence(.namePrefix, .possible, specificity: name.count)
            }
            return nil
        }
    }
}
